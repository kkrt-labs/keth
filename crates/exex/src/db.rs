use alloy_primitives::{Address, B256, U256};
use cairo_vm::{
    air_private_input::AirPrivateInput, air_public_input::PublicInput,
    vm::trace::trace_entry::RelocatedTraceEntry, Felt252,
};
use reth_primitives::{
    revm_primitives::{AccountInfo, Bytecode},
    SealedBlockWithSenders,
};
use reth_provider::OriginalValuesKnown;
use reth_revm::db::BundleState;
use rusqlite::Connection;
use std::{
    ops::{Deref, DerefMut},
    str::FromStr,
    sync::{Arc, Mutex, MutexGuard},
};

/// A struct representing the database, encapsulating a connection to the `SQLite` database.
///
/// The connection is protected by a `Mutex` for thread-safe access and is shared across
/// instances using `Arc`.
#[derive(Debug)]
pub struct Database(Arc<Mutex<Connection>>);

impl Deref for Database {
    type Target = Arc<Mutex<Connection>>;

    fn deref(&self) -> &Self::Target {
        &self.0
    }
}

impl DerefMut for Database {
    fn deref_mut(&mut self) -> &mut Self::Target {
        &mut self.0
    }
}

impl Database {
    /// Creates a new `Database` instance with the provided `SQLite` [`Connection`].
    pub fn new(connection: Connection) -> eyre::Result<Self> {
        // Create the database instance and create the required tables.
        let database = Self(Arc::new(Mutex::new(connection)));
        database.create_tables()?;
        Ok(database)
    }

    /// Acquires a lock on the database connection and returns a `MutexGuard` for access.
    fn connection(&self) -> MutexGuard<'_, Connection> {
        self.lock().expect("failed to acquire database lock")
    }

    /// Creates the necessary tables in the `SQLite` database if they do not already exist.
    ///
    /// This function sets up the following tables:
    /// - `block`: Stores blocks with a unique block number and associated data.
    /// - `account`: Stores account data with a unique address.
    fn create_tables(&self) -> eyre::Result<()> {
        // Acquires a lock on the database connection and executes SQL commands to create tables.
        self.connection().execute_batch(
            "CREATE TABLE IF NOT EXISTS block (
                id     INTEGER PRIMARY KEY,
                number TEXT UNIQUE,
                data   TEXT
            );
            CREATE TABLE IF NOT EXISTS account (
                id      INTEGER PRIMARY KEY,
                address TEXT UNIQUE,
                data    TEXT
            );
            CREATE TABLE IF NOT EXISTS trace (
                id                  INTEGER PRIMARY KEY,
                number              TEXT,
                execution           TEXT,
                memory              TEXT,
                air_public_input    TEXT,
                air_private_input   TEXT
            );
            ",
        )?;
        Ok(())
    }

    /// Inserts a block with its associated bundle into the database.
    #[allow(clippy::significant_drop_tightening)]
    pub fn insert_block_with_bundle(
        &self,
        block: &SealedBlockWithSenders,
        bundle: BundleState,
    ) -> eyre::Result<()> {
        // Acquire a database connection and begin a transaction.
        let mut connection = self.connection();
        let tx = connection.transaction()?;

        // Insert the block into the `block` table.
        tx.execute(
            "INSERT INTO block (number, data) VALUES (?, ?)",
            (block.header.number.to_string(), serde_json::to_string(block)?),
        )?;

        // Convert the `BundleState` into plain state changes and reverts.
        let (changeset, _) = bundle.into_plain_state_and_reverts(OriginalValuesKnown::Yes);

        // Process and insert or update account information based on the changeset.
        for (address, account) in changeset.accounts {
            if let Some(account) = account {
                // Insert or update the account in the `account` table.
                tx.execute(
                "INSERT INTO account (address, data) VALUES (?, ?) ON CONFLICT(address) DO UPDATE SET data = excluded.data",
                (address.to_string(), serde_json::to_string(&account)?))?;
            } else {
                // Delete the account from the `account` table if it was removed.
                tx.execute("DELETE FROM account WHERE address = ?", (address.to_string(),))?;
            }
        }

        // Commit the transaction to persist all changes.
        tx.commit()?;

        Ok(())
    }

    /// Retrieves a block from the database using its block number.
    ///
    /// This function queries the database for a block with the specified block number.
    /// If the block is found, it is deserialized from its JSON representation into a
    /// [`SealedBlockWithSenders`] struct. If the block is not found, `None` is returned.
    pub fn block(&self, number: U256) -> eyre::Result<Option<SealedBlockWithSenders>> {
        // Executes a SQL query to select the block data as a JSON string based on the block number.
        let block = self.connection().query_row::<String, _, _>(
            "SELECT data FROM block WHERE number = ?",
            (number.to_string(),),
            // Retrieves the first column of the result row as a string.
            |row| row.get(0),
        );

        match block {
            // If the block is found, deserialize the JSON string into [`SealedBlockWithSenders`].
            Ok(data) => Ok(Some(serde_json::from_str(&data)?)),
            // If no rows are returned by the query, it means the block does not exist in the
            // database.
            Err(rusqlite::Error::QueryReturnedNoRows) => Ok(None),
            // If any other error occurs, convert it into an eyre error and return.
            Err(e) => Err(e.into()),
        }
    }

    /// Retrieves the latest block from the database.
    ///
    /// This function queries the database for the block with the highest block number (interpreted
    /// as an integer) and returns it as a [`SealedBlockWithSenders`] struct. If an error occurs
    /// during the retrieval or deserialization of the block, the function will return an
    /// `eyre::Result` containing the error.
    pub fn latest_block(&self) -> eyre::Result<Option<SealedBlockWithSenders>> {
        // Prepare a SQL query to select the block data as a JSON string with the highest block
        // number.
        let block = self.connection().query_row::<String, _, _>(
            "SELECT data FROM block ORDER BY CAST(number AS INTEGER) DESC LIMIT 1",
            [],
            |row| row.get(0),
        );

        match block {
            // If the block is found, deserialize the JSON string into `SealedBlockWithSenders`.
            Ok(data) => Ok(Some(serde_json::from_str(&data)?)),
            // If no rows are returned by the query, it means the table is empty.
            Err(rusqlite::Error::QueryReturnedNoRows) => Ok(None),
            // If any other error occurs, convert it into an eyre error and return.
            Err(e) => Err(e.into()),
        }
    }

    /// Inserts an execution trace into the database.
    #[allow(clippy::significant_drop_tightening)]
    pub fn insert_execution_trace(
        &self,
        number: u64,
        trace: &[RelocatedTraceEntry],
        memory: &[Felt252],
        air_public_input: &PublicInput<'_>,
        air_private_input: &AirPrivateInput,
    ) -> eyre::Result<()> {
        // Acquire a database connection and begin a transaction.
        let mut connection = self.connection();
        let tx = connection.transaction()?;

        // Insert the trace into the `trace` table.
        tx.execute(
            "INSERT INTO trace (number, execution, memory, air_public_input, air_private_input) VALUES (?, ?, ?, ?, ?)",
            (number, serde_json::to_string(&trace)?, serde_json::to_string(&memory)?, serde_json::to_string(&air_public_input)?, serde_json::to_string(&air_private_input.0)?),
        )?;

        // Commit the transaction to persist all changes.
        tx.commit()?;

        Ok(())
    }

    /// Retrieves the execution trace and memory state for a specific block from the database.
    #[allow(clippy::significant_drop_tightening)]
    pub fn execution_trace(
        &self,
        number: u64,
    ) -> eyre::Result<Option<(Vec<RelocatedTraceEntry>, Vec<Felt252>)>> {
        // Executes a SQL query to select the trace data as a JSON string based on the block number.
        let connection = self.connection();
        let mut statement =
            connection.prepare("SELECT execution, memory FROM trace WHERE number = ?")?;
        let res: Result<(String, String), _> = statement
            .query_map([number.to_string()], |row| Ok((row.get(0)?, row.get(1)?)))?
            .next()
            .ok_or_else(|| eyre::eyre!("No trace found for block"))?;

        match res {
            // If the trace is found, deserialize the JSON strings into `(Vec<RelocatedTraceEntry>,
            // Vec<Felt252>)`.
            Ok((trace, memory)) => {
                Ok(Some((serde_json::from_str(&trace)?, serde_json::from_str(&memory)?)))
            }
            // If no rows are returned by the query, it means the trace does not exist for the given
            // block in the database.
            Err(rusqlite::Error::QueryReturnedNoRows) => Ok(None),
            // If any other error occurs, convert it into an eyre error and return.
            Err(e) => Err(e.into()),
        }
    }

    /// Inserts a new account if it doesn't exist or updates it if it does.
    pub fn set_account(&self, address: Address, account_info: &AccountInfo) -> eyre::Result<()> {
        self.connection().execute(
            "INSERT INTO account (address, data) VALUES (?, ?) ON CONFLICT(address) DO UPDATE SET data = excluded.data",
            (address.to_string(), serde_json::to_string(&account_info)?),
        )?;

        Ok(())
    }

    /// Retrieves an account from the database using its address.
    pub fn account(&self, address: Address) -> eyre::Result<Option<AccountInfo>> {
        let account = self.connection().query_row::<String, _, _>(
            "SELECT data FROM account WHERE address = ?",
            (address.to_string(),),
            |row| row.get(0),
        );

        match account {
            Ok(account_info) => Ok(Some(serde_json::from_str(&account_info)?)),
            Err(rusqlite::Error::QueryReturnedNoRows) => Ok(None),
            Err(e) => Err(e.into()),
        }
    }
}

impl reth_revm::Database for Database {
    type Error = eyre::Report;

    fn basic(&mut self, address: Address) -> Result<Option<AccountInfo>, Self::Error> {
        self.account(address)
    }

    fn code_by_hash(&mut self, _code_hash: B256) -> Result<Bytecode, Self::Error> {
        Ok(Default::default())
    }

    fn storage(&mut self, _address: Address, _index: U256) -> Result<U256, Self::Error> {
        Ok(Default::default())
    }

    fn block_hash(&mut self, number: u64) -> Result<B256, Self::Error> {
        let block_hash = self.connection().query_row::<String, _, _>(
            "SELECT hash FROM block WHERE number = ?",
            (number.to_string(),),
            |row| row.get(0),
        );
        match block_hash {
            Ok(data) => Ok(B256::from_str(&data).unwrap()),
            // No special handling for `QueryReturnedNoRows` is needed, because revm does block
            // number bound checks on its own.
            // See https://github.com/bluealloy/revm/blob/1ca3d39f6a9e9778f8eb0fcb74fe529345a531b4/crates/interpreter/src/instructions/host.rs#L106-L123.
            Err(err) => Err(err.into()),
        }
    }
}
