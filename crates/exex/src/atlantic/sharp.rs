use super::{error::SharpSdkError, model::QueryResponse, prover::ProverVersion};
use crate::atlantic::endpoints::{
    HealthCheckEndpoint, L2Endpoints, ProgramRegistryEndpoint, SharpQueriesEndpoints,
};
use reqwest::Client;
use url::Url;

/// The Sharp SDK for interacting with the Sharp API.
#[derive(Debug, Clone)]
pub struct SharpSdk {
    /// The API key to use for authentication.
    pub api_key: String,
    /// The L2 endpoints.
    pub l2: L2Endpoints,
    /// The Sharp queries endpoints.
    pub sharp_queries: SharpQueriesEndpoints,
    /// The health check endpoint.
    pub health_check: HealthCheckEndpoint,
    /// The program registry endpoint.
    pub program_registry: ProgramRegistryEndpoint,
}

impl SharpSdk {
    /// Create a new Sharp SDK instance from:
    /// - an API key
    /// - a base URL
    pub fn new(api_key: String, base_url: &Url) -> Result<Self, SharpSdkError> {
        Ok(Self {
            api_key,
            l2: L2Endpoints::new(base_url)?,
            sharp_queries: SharpQueriesEndpoints::new(base_url)?,
            health_check: HealthCheckEndpoint::new(base_url)?,
            program_registry: ProgramRegistryEndpoint::new(base_url)?,
        })
    }

    pub async fn proof_generation(
        &self,
        pie_file: Vec<u8>,
        layout: &str,
        prover: ProverVersion,
    ) -> Result<QueryResponse, SharpSdkError> {
        // Create the form data
        let form = reqwest::multipart::Form::new()
            .part(
                "pieFile",
                reqwest::multipart::Part::bytes(pie_file)
                    .file_name("pie.zip")
                    .mime_str("application/zip")?,
            )
            .text("layout", layout.to_string())
            .text("prover", prover.to_string());

        // Create a new HTTP client
        let client = Client::new();

        // Construct the full URL including the API key
        let url = format!("{}?apiKey={}", self.l2.proof_generation, self.api_key);

        // Make a POST request to the proof generation endpoint
        let response =
            client.post(&url).multipart(form).send().await?.json::<QueryResponse>().await?;

        Ok(response)
    }
}
