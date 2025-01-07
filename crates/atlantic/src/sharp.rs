use super::{error::SharpSdkError, model::QueryResponse, prover::ProverVersion};
use crate::endpoints::ProofTraceEndpoints;
use reqwest::Client;
use url::Url;

/// The Sharp SDK for interacting with the Sharp API.
#[derive(Debug, Clone)]
pub struct SharpSdk {
    /// The API key to use for authentication.
    pub api_key: String,
    /// The base URL for the Sharp API.
    pub base_url: Url,
}

impl SharpSdk {
    /// Create a new Sharp SDK instance
    pub const fn new(api_key: String, base_url: Url) -> Self {
        Self { api_key, base_url }
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

        // Construct the full URL.
        let url = ProofTraceEndpoints::ProofGeneration.url(&self.base_url)?;

        // Send the request
        let response = client
            .post(url)
            .query(&[("apiKey", &self.api_key)])
            .multipart(form)
            .send()
            .await?
            .json::<QueryResponse>()
            .await?;

        Ok(response)
    }
}
