use super::error::SharpSdkError;
use url::Url;

/// The L2 endpoints.
#[derive(Debug, Clone)]
pub struct L2Endpoints {
    /// Submit an Atlantic proof generation query
    pub proof_generation: Url,
    /// Submit an Atlantic trace generation query
    pub trace_generation: Url,
    /// Submit an Atlantic trace generation and proof generation query
    pub trace_generation_proof_generation: Url,
    /// Submit a L2 Atlantic query
    pub atlantic_query: Url,
    /// Submit a L2 Atlantic proof generation and proof verification query
    pub proof_generation_verification: Url,
    /// Submit a L2 Atlantic proof verification query
    pub proof_verification: Url,
}

impl L2Endpoints {
    pub fn new(base_url: &Url) -> Result<Self, SharpSdkError> {
        Ok(Self {
            proof_generation: base_url.join("proof-generation")?,
            trace_generation: base_url.join("trace-generation")?,
            trace_generation_proof_generation: base_url
                .join("trace-generation-proof-generation")?,
            atlantic_query: base_url.join("l2/atlantic-query")?,
            proof_generation_verification: base_url
                .join("l2/atlantic-query/proof-generation-verification")?,
            proof_verification: base_url.join("l2/atlantic-query/proof-verification")?,
        })
    }
}

/// The Sharp queries endpoints.
#[derive(Debug, Clone)]
pub struct SharpQueriesEndpoints {
    /// Get the list of Atlantic queries submitted by the user
    pub queries: Url,
    /// Get the details of a specific Atlantic query
    pub query: Url,
    /// Get the list of jobs for a specific Atlantic query
    pub query_jobs: Url,
}

impl SharpQueriesEndpoints {
    pub fn new(base_url: &Url) -> Result<Self, SharpSdkError> {
        Ok(Self {
            queries: base_url.join("atlantic-queries")?,
            query: base_url.join("atlantic-query")?,
            query_jobs: base_url.join("atlantic-query-jobs")?,
        })
    }
}

/// The health check endpoint.
#[derive(Debug, Clone)]
pub struct HealthCheckEndpoint {
    /// Check if the server is alive
    pub is_alive: Url,
}

impl HealthCheckEndpoint {
    pub fn new(base_url: &Url) -> Result<Self, SharpSdkError> {
        Ok(Self { is_alive: base_url.join("is-alive")? })
    }
}

/// The program registry endpoint.
#[derive(Debug, Clone)]
pub struct ProgramRegistryEndpoint {
    /// Submit a program to the program registry
    pub submit_program: Url,
}

impl ProgramRegistryEndpoint {
    pub fn new(base_url: &Url) -> Result<Self, SharpSdkError> {
        Ok(Self { submit_program: base_url.join("submit-program")? })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_l2_endpoints_invalid_base_url() {
        // Test with an invalid base URL
        let base_url = Url::parse("invalid-url");
        assert!(base_url.is_err(), "Expected base URL parsing to fail");
    }

    #[test]
    fn test_l2_endpoints_valid_base_url_trailing_slash() {
        let base_url = Url::parse("https://example.com/")
            .expect("Failed to parse base URL with trailing slash");
        let endpoints = L2Endpoints::new(&base_url).expect("Failed to create L2Endpoints");

        // Check that URLs are constructed correctly even with a trailing slash in base URL
        assert_eq!(
            endpoints.proof_generation,
            Url::parse("https://example.com/proof-generation").unwrap()
        );
        assert_eq!(
            endpoints.trace_generation,
            Url::parse("https://example.com/trace-generation").unwrap()
        );
        assert_eq!(
            endpoints.trace_generation_proof_generation,
            Url::parse("https://example.com/trace-generation-proof-generation").unwrap()
        );
        assert_eq!(
            endpoints.atlantic_query,
            Url::parse("https://example.com/l2/atlantic-query").unwrap()
        );
        assert_eq!(
            endpoints.proof_generation_verification,
            Url::parse("https://example.com/l2/atlantic-query/proof-generation-verification")
                .unwrap()
        );
        assert_eq!(
            endpoints.proof_verification,
            Url::parse("https://example.com/l2/atlantic-query/proof-verification").unwrap()
        );
    }

    #[test]
    fn test_l2_endpoints_valid_base_url() {
        let base_url = Url::parse("https://example.com").expect("Failed to parse base URL");
        let endpoints = L2Endpoints::new(&base_url).expect("Failed to create L2Endpoints");

        // Check that URLs are constructed correctly even without a trailing slash in base URL
        assert_eq!(
            endpoints.proof_generation,
            Url::parse("https://example.com/proof-generation").unwrap()
        );
        assert_eq!(
            endpoints.trace_generation,
            Url::parse("https://example.com/trace-generation").unwrap()
        );
        assert_eq!(
            endpoints.trace_generation_proof_generation,
            Url::parse("https://example.com/trace-generation-proof-generation").unwrap()
        );
        assert_eq!(
            endpoints.atlantic_query,
            Url::parse("https://example.com/l2/atlantic-query").unwrap()
        );
        assert_eq!(
            endpoints.proof_generation_verification,
            Url::parse("https://example.com/l2/atlantic-query/proof-generation-verification")
                .unwrap()
        );
        assert_eq!(
            endpoints.proof_verification,
            Url::parse("https://example.com/l2/atlantic-query/proof-verification").unwrap()
        );
    }

    #[test]
    fn test_sharp_queries_endpoints_invalid_base_url() {
        // Test with an invalid base URL
        let base_url = Url::parse("invalid-url");
        assert!(base_url.is_err(), "Expected base URL parsing to fail");
    }

    #[test]
    fn test_sharp_queries_endpoints_valid_base_url_trailing_slash() {
        let base_url = Url::parse("https://example.com/")
            .expect("Failed to parse base URL with trailing slash");
        let endpoints =
            SharpQueriesEndpoints::new(&base_url).expect("Failed to create SharpQueriesEndpoints");

        // Check that URLs are constructed correctly even with a trailing slash in base URL
        assert_eq!(endpoints.queries, Url::parse("https://example.com/atlantic-queries").unwrap());
        assert_eq!(endpoints.query, Url::parse("https://example.com/atlantic-query").unwrap());
        assert_eq!(
            endpoints.query_jobs,
            Url::parse("https://example.com/atlantic-query-jobs").unwrap()
        );
    }

    #[test]
    fn test_sharp_queries_endpoints_valid_base_url() {
        let base_url = Url::parse("https://example.com").expect("Failed to parse base URL");
        let endpoints =
            SharpQueriesEndpoints::new(&base_url).expect("Failed to create SharpQueriesEndpoints");

        // Check that URLs are constructed correctly even without a trailing slash in base URL
        assert_eq!(endpoints.queries, Url::parse("https://example.com/atlantic-queries").unwrap());
        assert_eq!(endpoints.query, Url::parse("https://example.com/atlantic-query").unwrap());
        assert_eq!(
            endpoints.query_jobs,
            Url::parse("https://example.com/atlantic-query-jobs").unwrap()
        );
    }

    #[test]
    fn test_health_check_endpoint_invalid_base_url() {
        // Test with an invalid base URL
        let base_url = Url::parse("invalid-url");
        assert!(base_url.is_err(), "Expected base URL parsing to fail");
    }

    #[test]
    fn test_health_check_endpoint_valid_base_url() {
        let base_url = Url::parse("https://example.com").expect("Failed to parse base URL");
        let endpoint =
            HealthCheckEndpoint::new(&base_url).expect("Failed to create HealthCheckEndpoint");

        // Check that the URL is constructed correctly
        assert_eq!(endpoint.is_alive, Url::parse("https://example.com/is-alive").unwrap());
    }

    #[test]
    fn test_health_check_endpoint_valid_base_url_trailing_slash() {
        let base_url = Url::parse("https://example.com/")
            .expect("Failed to parse base URL with trailing slash");
        let endpoint =
            HealthCheckEndpoint::new(&base_url).expect("Failed to create HealthCheckEndpoint");

        // Check that the URL is constructed correctly even with a trailing slash
        assert_eq!(endpoint.is_alive, Url::parse("https://example.com/is-alive").unwrap());
    }

    #[test]
    fn test_program_registry_endpoint_invalid_base_url() {
        // Test with an invalid base URL
        let base_url = Url::parse("invalid-url");
        assert!(base_url.is_err(), "Expected base URL parsing to fail");
    }

    #[test]
    fn test_program_registry_endpoint_valid_base_url() {
        let base_url = Url::parse("https://example.com").expect("Failed to parse base URL");
        let endpoint = ProgramRegistryEndpoint::new(&base_url)
            .expect("Failed to create ProgramRegistryEndpoint");

        // Check that the URL is constructed correctly
        assert_eq!(
            endpoint.submit_program,
            Url::parse("https://example.com/submit-program").unwrap()
        );
    }

    #[test]
    fn test_program_registry_endpoint_valid_base_url_trailing_slash() {
        let base_url = Url::parse("https://example.com/")
            .expect("Failed to parse base URL with trailing slash");
        let endpoint = ProgramRegistryEndpoint::new(&base_url)
            .expect("Failed to create ProgramRegistryEndpoint");

        // Check that the URL is constructed correctly even with a trailing slash
        assert_eq!(
            endpoint.submit_program,
            Url::parse("https://example.com/submit-program").unwrap()
        );
    }
}
