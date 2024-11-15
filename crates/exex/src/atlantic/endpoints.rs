use super::error::SharpSdkError;
use url::Url;

/// Proof and trace generation endpoints.
#[derive(Debug, Clone)]
pub enum ProofTraceEndpoints {
    /// Submit a Atlantic proof generation query.
    ProofGeneration,
    /// Submit a Atlantic trace generation query.
    TraceGeneration,
    /// Submit a Atlantic trace generation and proof generation query.
    TraceGenerationProofGeneration,
}

impl ProofTraceEndpoints {
    pub fn url(&self, base_url: &Url) -> Result<Url, SharpSdkError> {
        match self {
            Self::ProofGeneration => base_url.join("proof-generation"),
            Self::TraceGeneration => base_url.join("trace-generation"),
            Self::TraceGenerationProofGeneration => {
                base_url.join("trace-generation-proof-generation")
            }
        }
        .map_err(SharpSdkError::from)
    }
}

/// The L2 endpoints.
#[derive(Debug, Clone)]
pub enum L2Endpoints {
    /// Submit a Atlantic L2 query.
    AtlanticQuery,
    /// Submit a Atlantic proof generation and verification query.
    ProofGenerationVerification,
    /// Submit a Atlantic proof verification query.
    ProofVerification,
}

impl L2Endpoints {
    pub fn url(&self, base_url: &Url) -> Result<Url, SharpSdkError> {
        match self {
            Self::AtlanticQuery => base_url.join("l2/atlantic-query"),
            Self::ProofGenerationVerification => {
                base_url.join("l2/atlantic-query/proof-generation-verification")
            }
            Self::ProofVerification => base_url.join("l2/atlantic-query/proof-verification"),
        }
        .map_err(SharpSdkError::from)
    }
}

/// The Sharp queries endpoints.
#[derive(Debug, Clone)]
pub enum SharpQueryEndpoints {
    /// Get the list of Atlantic queries that have been submitted.
    Queries,
    /// Get an Atlantic query.
    Query,
    /// Get the Atlantic query jobs for a given Atlantic query.
    QueryJobs,
}

impl SharpQueryEndpoints {
    pub fn url(&self, base_url: &Url) -> Result<Url, SharpSdkError> {
        match self {
            Self::Queries => base_url.join("atlantic-queries"),
            Self::Query => base_url.join("atlantic-query"),
            Self::QueryJobs => base_url.join("atlantic-query-jobs"),
        }
        .map_err(SharpSdkError::from)
    }
}

/// The health check endpoint.
#[derive(Debug, Clone)]
pub enum HealthCheckEndpoints {
    /// Check if the server is alive.
    IsAlive,
}

impl HealthCheckEndpoints {
    pub fn url(&self, base_url: &Url) -> Result<Url, SharpSdkError> {
        match self {
            Self::IsAlive => base_url.join("is-alive"),
        }
        .map_err(SharpSdkError::from)
    }
}

/// The program registry endpoint.
#[derive(Debug, Clone)]
pub enum ProgramRegistryEndpoints {
    /// Submit a program to the program registry.
    SubmitProgram,
}

impl ProgramRegistryEndpoints {
    pub fn url(&self, base_url: &Url) -> Result<Url, SharpSdkError> {
        match self {
            Self::SubmitProgram => base_url.join("submit-program"),
        }
        .map_err(SharpSdkError::from)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_proof_trace_endpoint_urls() {
        let base_url = Url::parse("https://example.com/").unwrap();

        // Test ProofTraceEndpoints URLs
        assert_eq!(
            ProofTraceEndpoints::ProofGeneration.url(&base_url).unwrap(),
            Url::parse("https://example.com/proof-generation").unwrap()
        );
        assert_eq!(
            ProofTraceEndpoints::TraceGeneration.url(&base_url).unwrap(),
            Url::parse("https://example.com/trace-generation").unwrap()
        );
        assert_eq!(
            ProofTraceEndpoints::TraceGenerationProofGeneration.url(&base_url).unwrap(),
            Url::parse("https://example.com/trace-generation-proof-generation").unwrap()
        );
    }

    #[test]
    fn test_l2_endpoint_urls() {
        let base_url = Url::parse("https://example.com/").unwrap();

        // Test L2Endpoints URLs
        assert_eq!(
            L2Endpoints::AtlanticQuery.url(&base_url).unwrap(),
            Url::parse("https://example.com/l2/atlantic-query").unwrap()
        );
        assert_eq!(
            L2Endpoints::ProofGenerationVerification.url(&base_url).unwrap(),
            Url::parse("https://example.com/l2/atlantic-query/proof-generation-verification")
                .unwrap()
        );
        assert_eq!(
            L2Endpoints::ProofVerification.url(&base_url).unwrap(),
            Url::parse("https://example.com/l2/atlantic-query/proof-verification").unwrap()
        );
    }

    #[test]
    fn test_sharp_query_endpoint_urls() {
        let base_url = Url::parse("https://example.com/").unwrap();

        // Test SharpQueryEndpoints URLs
        assert_eq!(
            SharpQueryEndpoints::Queries.url(&base_url).unwrap(),
            Url::parse("https://example.com/atlantic-queries").unwrap()
        );
        assert_eq!(
            SharpQueryEndpoints::Query.url(&base_url).unwrap(),
            Url::parse("https://example.com/atlantic-query").unwrap()
        );
        assert_eq!(
            SharpQueryEndpoints::QueryJobs.url(&base_url).unwrap(),
            Url::parse("https://example.com/atlantic-query-jobs").unwrap()
        );
    }

    #[test]
    fn test_health_check_endpoint_url() {
        let base_url = Url::parse("https://example.com/").unwrap();

        // Test HealthCheckEndpoints URL
        assert_eq!(
            HealthCheckEndpoints::IsAlive.url(&base_url).unwrap(),
            Url::parse("https://example.com/is-alive").unwrap()
        );
    }

    #[test]
    fn test_program_registry_endpoint_url() {
        let base_url = Url::parse("https://example.com/").unwrap();

        // Test ProgramRegistryEndpoints URL
        assert_eq!(
            ProgramRegistryEndpoints::SubmitProgram.url(&base_url).unwrap(),
            Url::parse("https://example.com/submit-program").unwrap()
        );
    }
}
