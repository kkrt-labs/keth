use std::fmt;

#[derive(Debug)]
pub enum ProverVersion {
    Starkware,
    Herodotus,
}

impl fmt::Display for ProverVersion {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        let version_str = match self {
            Self::Starkware => "starkware_sharp",
            Self::Herodotus => "herodotus_stone",
        };
        write!(f, "{version_str}")
    }
}

#[cfg(test)]
mod tests {
    use super::ProverVersion;

    #[test]
    fn test_prover_version_to_string() {
        let version_starkware = ProverVersion::Starkware;
        assert_eq!(version_starkware.to_string(), "starkware_sharp");

        let version_herodotus = ProverVersion::Herodotus;
        assert_eq!(version_herodotus.to_string(), "herodotus_stone");
    }
}
