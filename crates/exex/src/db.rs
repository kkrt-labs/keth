use reth_primitives::{
    revm_primitives::{AccountInfo, Bytecode},
    Address, Bytes, SealedBlockWithSenders, StorageEntry, B256, U256,
};
use reth_provider::{bundle_state::StorageRevertsIter, OriginalValuesKnown};
use reth_revm::db::{
    states::{PlainStorageChangeset, PlainStorageRevert},
    BundleState,
};
use rusqlite::Connection;
use std::{
    collections::HashMap,
    ops::{Deref, DerefMut},
    str::FromStr,
    sync::{Arc, Mutex, MutexGuard},
};

/// Types used inside RevertsInit to initialize revms reverts.
pub type AccountRevertInit = (Option<Option<AccountInfo>>, Vec<StorageEntry>);

/// Type used to initialize revms reverts.
pub type RevertsInit = HashMap<Address, AccountRevertInit>;

/// A struct representing the database, encapsulating a connection to the SQLite database.
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
    /// Creates a new `Database` instance with the provided SQLite `Connection`.
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

    /// Creates the necessary tables in the SQLite database if they do not already exist.
    ///
    /// This function sets up the following tables:
    /// - `block`: Stores blocks with a unique block number and associated data.
    /// - `account`: Stores account data with a unique address.
    /// - `account_revert`: Stores data needed to revert account changes.
    /// - `storage`: Stores storage data with a unique combination of address and key.
    /// - `storage_revert`: Stores data needed to revert storage changes.
    /// - `bytecode`: Stores bytecode associated with a unique hash.
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
            CREATE TABLE IF NOT EXISTS account_revert (
                id           INTEGER PRIMARY KEY,
                block_number TEXT,
                address      TEXT,
                data         TEXT,
                UNIQUE (block_number, address)
            );
            CREATE TABLE IF NOT EXISTS storage (
                id      INTEGER PRIMARY KEY,
                address TEXT,
                key     TEXT,
                data    TEXT,
                UNIQUE (address, key)
            );
            CREATE TABLE IF NOT EXISTS storage_revert (
                id           INTEGER PRIMARY KEY,
                block_number TEXT,
                address      TEXT,
                key          TEXT,
                data         TEXT,
                UNIQUE (block_number, address, key)
            );
            CREATE TABLE IF NOT EXISTS bytecode (
                id   INTEGER PRIMARY KEY,
                hash TEXT UNIQUE,
                data TEXT
            );",
        )?;
        Ok(())
    }

    /// Inserts a block with its associated bundle into the database.
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
        let (changeset, reverts) = bundle.into_plain_state_and_reverts(OriginalValuesKnown::Yes);

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

        // Ensure that there is at most one block in account reverts.
        if reverts.accounts.len() > 1 {
            eyre::bail!("too many blocks in account reverts");
        }

        if let Some(account_reverts) = reverts.accounts.into_iter().next() {
            // Insert or update account reverts in the `account_revert` table.
            for (address, account) in account_reverts {
                tx.execute(
                "INSERT INTO account_revert (block_number, address, data) VALUES (?, ?, ?) ON CONFLICT(block_number, address) DO UPDATE SET data = excluded.data",
                (block.header.number.to_string(), address.to_string(), serde_json::to_string(&account)?),
            )?;
            }
        }

        // Process storage changes in the changeset.
        for PlainStorageChangeset { address, wipe_storage, storage } in changeset.storage {
            if wipe_storage {
                // Delete all storage entries for the given address if `wipe_storage` is true.
                tx.execute("DELETE FROM storage WHERE address = ?", (address.to_string(),))?;
            }

            // Insert or update storage entries in the `storage` table.
            for (key, data) in storage {
                tx.execute(
                "INSERT INTO storage (address, key, data) VALUES (?, ?, ?) ON CONFLICT(address, key) DO UPDATE SET data = excluded.data",
                (address.to_string(), B256::from(key).to_string(), data.to_string()),
            )?;
            }
        }

        // Ensure that there is at most one block in storage reverts.
        if reverts.storage.len() > 1 {
            eyre::bail!("too many blocks in storage reverts");
        }

        if let Some(storage_reverts) = reverts.storage.into_iter().next() {
            // Process and insert or update storage reverts in the `storage_revert` table.
            for PlainStorageRevert { address, wiped, storage_revert } in storage_reverts {
                let storage = storage_revert
                    .into_iter()
                    .map(|(k, v)| (B256::new(k.to_be_bytes()), v))
                    .collect::<Vec<_>>();
                let wiped_storage = if wiped { get_storages(&tx, address)? } else { Vec::new() };
                for (key, data) in StorageRevertsIter::new(storage, wiped_storage) {
                    tx.execute(
                    "INSERT INTO storage_revert (block_number, address, key, data) VALUES (?, ?, ?, ?) ON CONFLICT(block_number, address, key) DO UPDATE SET data = excluded.data",
                    (block.header.number.to_string(), address.to_string(), key.to_string(), data.to_string()),
                )?;
                }
            }
        }

        // Insert or update bytecode information in the `bytecode` table.
        for (hash, bytecode) in changeset.contracts {
            tx.execute(
                "INSERT INTO bytecode (hash, data) VALUES (?, ?) ON CONFLICT(hash) DO NOTHING",
                (hash.to_string(), bytecode.bytecode().to_string()),
            )?;
        }

        // Commit the transaction to persist all changes.
        tx.commit()?;

        Ok(())
    }

    /// Retrieves a block from the database using its block number.
    ///
    /// This function queries the database for a block with the specified block number.
    /// If the block is found, it is deserialized from its JSON representation into a
    /// `SealedBlockWithSenders` struct. If the block is not found, `None` is returned.
    pub fn get_block(&self, number: U256) -> eyre::Result<Option<SealedBlockWithSenders>> {
        // Executes a SQL query to select the block data as a JSON string based on the block number.
        let block = self.connection().query_row::<String, _, _>(
            "SELECT data FROM block WHERE number = ?",
            (number.to_string(),),
            // Retrieves the first column of the result row as a string.
            |row| row.get(0),
        );

        match block {
            // If the block is found, deserialize the JSON string into `SealedBlockWithSenders`.
            Ok(data) => Ok(Some(serde_json::from_str(&data)?)),
            // If no rows are returned by the query, it means the block does not exist in the
            // database.
            Err(rusqlite::Error::QueryReturnedNoRows) => Ok(None),
            // If any other error occurs, convert it into an eyre error and return.
            Err(e) => Err(e.into()),
        }
    }

    /// Inserts a new account if it doesn't exist or updates it if it does.
    pub fn upsert_account(
        &self,
        address: Address,
        f: impl FnOnce(Option<AccountInfo>) -> eyre::Result<AccountInfo>,
    ) -> eyre::Result<()> {
        upsert_account(&self.connection(), address, f)
    }

    /// Retrieves an account from the database using its address.
    pub fn get_account(&self, address: Address) -> eyre::Result<Option<AccountInfo>> {
        get_account(&self.connection(), address)
    }
}

/// Insert new account if it does not exist, update otherwise. The provided closure is called
/// with the current account, if it exists. Connection can be either
/// [rusqlite::Transaction] or [rusqlite::Connection].
fn upsert_account(
    connection: &Connection,
    address: Address,
    f: impl FnOnce(Option<AccountInfo>) -> eyre::Result<AccountInfo>,
) -> eyre::Result<()> {
    let account = get_account(connection, address)?;
    let account = f(account)?;
    connection.execute(
        "INSERT INTO account (address, data) VALUES (?, ?) ON CONFLICT(address) DO UPDATE SET data = excluded.data",
        (address.to_string(), serde_json::to_string(&account)?),
    )?;

    Ok(())
}

/// Get account by address using the database connection. Connection can be either
/// [rusqlite::Transaction] or [rusqlite::Connection].
fn get_account(connection: &Connection, address: Address) -> eyre::Result<Option<AccountInfo>> {
    match connection.query_row::<String, _, _>(
        "SELECT data FROM account WHERE address = ?",
        (address.to_string(),),
        |row| row.get(0),
    ) {
        Ok(account_info) => Ok(Some(serde_json::from_str(&account_info)?)),
        Err(rusqlite::Error::QueryReturnedNoRows) => Ok(None),
        Err(e) => Err(e.into()),
    }
}

/// Get all storages for the provided address using the database connection. Connection can be
/// either [rusqlite::Transaction] or [rusqlite::Connection].
fn get_storages(connection: &Connection, address: Address) -> eyre::Result<Vec<(B256, U256)>> {
    connection
        .prepare("SELECT key, data FROM storage WHERE address = ?")?
        .query((address.to_string(),))?
        .mapped(|row| {
            Ok((
                B256::from_str(row.get_ref(0)?.as_str()?),
                U256::from_str(row.get_ref(1)?.as_str()?),
            ))
        })
        .map(|result| {
            let (key, data) = result?;
            Ok((key?, data?))
        })
        .collect()
}

/// Get storage for the provided address by key using the database connection. Connection can be
/// either [rusqlite::Transaction] or [rusqlite::Connection].
fn get_storage(connection: &Connection, address: Address, key: B256) -> eyre::Result<Option<U256>> {
    match connection.query_row::<String, _, _>(
        "SELECT data FROM storage WHERE address = ? AND key = ?",
        (address.to_string(), key.to_string()),
        |row| row.get(0),
    ) {
        Ok(data) => Ok(Some(U256::from_str(&data)?)),
        Err(rusqlite::Error::QueryReturnedNoRows) => Ok(None),
        Err(e) => Err(e.into()),
    }
}

impl reth_revm::Database for Database {
    type Error = eyre::Report;

    fn basic(&mut self, address: Address) -> Result<Option<AccountInfo>, Self::Error> {
        self.get_account(address)
    }

    fn code_by_hash(&mut self, code_hash: B256) -> Result<Bytecode, Self::Error> {
        let bytecode = self.connection().query_row::<String, _, _>(
            "SELECT data FROM bytecode WHERE hash = ?",
            (code_hash.to_string(),),
            |row| row.get(0),
        );
        match bytecode {
            Ok(data) => Ok(Bytecode::new_raw(Bytes::from_str(&data).unwrap())),
            Err(rusqlite::Error::QueryReturnedNoRows) => Ok(Bytecode::default()),
            Err(err) => Err(err.into()),
        }
    }

    fn storage(&mut self, address: Address, index: U256) -> Result<U256, Self::Error> {
        get_storage(&self.connection(), address, index.into()).map(|data| data.unwrap_or_default())
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
