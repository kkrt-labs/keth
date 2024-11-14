use serde::{Deserialize, Serialize};

#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq)]
pub struct Context {
    #[serde(rename = "proofPath")]
    pub proof_path: Option<String>,
}

#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq)]
pub struct Job {
    pub id: String,
    pub status: String,
    pub context: Option<Context>,
}

#[derive(Deserialize, Serialize, Debug, PartialEq, Eq)]
pub struct SharpQueryDetails {
    id: String,
    #[serde(rename = "submittedByClient")]
    submitted_by_client: String,
    status: String,
    step: Option<String>,
    #[serde(rename = "programHash")]
    program_hash: Option<String>,
    layout: Option<String>,
    #[serde(rename = "programFactHash")]
    program_fact_hash: Option<String>,
    price: String,
    #[serde(rename = "creditsUsed")]
    credits_used: usize,
    #[serde(rename = "isFactMocked")]
    is_fact_mocked: bool,
    prover: Option<String>,
    chain: String,
    steps: Vec<String>,
    #[serde(rename = "createdAt")]
    created_at: String,
    #[serde(rename = "completedAt")]
    completed_at: Option<String>,
}

#[derive(Serialize, Deserialize, Debug, PartialEq, Eq)]
pub struct QueryResponse {
    #[serde(rename = "sharpQueryId")]
    pub sharp_query_id: String,
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json;

    #[test]
    fn test_context_serialization() {
        let context = Context { proof_path: Some("path/to/proof".to_string()) };

        let serialized = serde_json::to_string(&context).expect("Failed to serialize Context");
        assert_eq!(
            serialized, r#"{"proofPath":"path/to/proof"}"#,
            "Serialization of Context is incorrect"
        );

        let deserialized: Context =
            serde_json::from_str(&serialized).expect("Failed to deserialize Context");
        assert_eq!(deserialized, context);
    }

    #[test]
    fn test_context_serialization_none() {
        let context = Context { proof_path: None };

        let serialized = serde_json::to_string(&context).expect("Failed to serialize Context");
        assert_eq!(
            serialized, r#"{"proofPath":null}"#,
            "Serialization of Context with None is incorrect"
        );

        let deserialized: Context =
            serde_json::from_str(&serialized).expect("Failed to deserialize Context");
        assert_eq!(deserialized, context);
    }

    #[test]
    fn test_job_serialization() {
        let job = Job {
            id: "job123".to_string(),
            status: "completed".to_string(),
            context: Some(Context { proof_path: Some("path/to/proof".to_string()) }),
        };

        let serialized = serde_json::to_string(&job).expect("Failed to serialize Job");
        assert_eq!(
            serialized,
            r#"{"id":"job123","status":"completed","context":{"proofPath":"path/to/proof"}}"#,
            "Serialization of Job is incorrect"
        );

        let deserialized: Job =
            serde_json::from_str(&serialized).expect("Failed to deserialize Job");
        assert_eq!(deserialized, job);
    }

    #[test]
    fn test_sharp_query_details_serialization() {
        let sharp_query = SharpQueryDetails {
            id: "query123".to_string(),
            submitted_by_client: "client456".to_string(),
            status: "running".to_string(),
            step: Some("proofgeneration".to_string()),
            program_hash: Some("hash789".to_string()),
            layout: Some("layout_xyz".to_string()),
            program_fact_hash: Some("fact_hash_abc".to_string()),
            price: "1000".to_string(),
            credits_used: 5,
            is_fact_mocked: false,
            prover: Some("starkware".to_string()),
            chain: "mainnet".to_string(),
            steps: vec!["step1".to_string(), "step2".to_string()],
            created_at: "2024-01-01T00:00:00Z".to_string(),
            completed_at: Some("2024-01-02T00:00:00Z".to_string()),
        };

        let serialized =
            serde_json::to_string(&sharp_query).expect("Failed to serialize SharpQueryDetails");
        let expected_serialization = r#"{
               "id":"query123",
               "submittedByClient":"client456",
               "status":"running",
               "step":"proofgeneration",
               "programHash":"hash789",
               "layout":"layout_xyz",
               "programFactHash":"fact_hash_abc",
               "price":"1000",
               "creditsUsed":5,
               "isFactMocked":false,
               "prover":"starkware",
               "chain":"mainnet",
               "steps":["step1","step2"],
               "createdAt":"2024-01-01T00:00:00Z",
               "completedAt":"2024-01-02T00:00:00Z"
           }"#
        .replace(['\n', ' '], ""); // Normalize whitespace for comparison
        assert_eq!(serialized, expected_serialization);

        let deserialized: SharpQueryDetails =
            serde_json::from_str(&serialized).expect("Failed to deserialize SharpQueryDetails");

        assert_eq!(deserialized, sharp_query);
    }

    #[test]
    fn test_query_response_serialization() {
        let query_response = QueryResponse { sharp_query_id: "query123".to_string() };

        let serialized =
            serde_json::to_string(&query_response).expect("Failed to serialize QueryResponse");
        assert_eq!(
            serialized, r#"{"sharpQueryId":"query123"}"#,
            "Serialization of QueryResponse is incorrect"
        );

        let deserialized: QueryResponse =
            serde_json::from_str(&serialized).expect("Failed to deserialize QueryResponse");
        assert_eq!(deserialized, query_response);
    }
}
