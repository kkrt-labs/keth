use serde::{Deserialize, Serialize};

#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct Context {
    pub proof_path: Option<String>,
}

#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq)]
pub struct Job {
    pub id: String,
    pub status: String,
    pub context: Option<Context>,
}

#[derive(Deserialize, Serialize, Debug, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct SharpQueryDetails {
    id: String,
    submitted_by_client: String,
    status: String,
    step: Option<String>,
    program_hash: Option<String>,
    layout: Option<String>,
    program_fact_hash: Option<String>,
    price: String,
    credits_used: usize,
    is_fact_mocked: bool,
    prover: Option<String>,
    chain: String,
    steps: Vec<String>,
    created_at: String,
    completed_at: Option<String>,
}

#[derive(Serialize, Deserialize, Debug, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct QueryResponse {
    pub atlantic_query_id: String,
}
