use thiserror::Error;

#[derive(Debug, Error)]
pub enum SharpSdkError {
    #[error(transparent)]
    ReqwestError(#[from] reqwest::Error),
    #[error(transparent)]
    SerdeError(#[from] serde_json::Error),
    #[error(transparent)]
    FileError(#[from] std::io::Error),
    #[error(transparent)]
    UrlParseError(#[from] url::ParseError),
    #[error("Missing program hash or program file")]
    MissingProgramHashOrFile,
}
