# ansible-role-csrmake

![.github/workflows/molecule.yml](https://github.com/AcroMedia/ansible-role-csrmake/workflows/.github/workflows/molecule.yml/badge.svg)

Installs (1) a utility for generating a private key + simple (single domain or wildcard domain) certificate signing requests, and (2) a utility for putting the resulting SSL/TLS certificate / intermediate files in place after the cert is signed and returned to you by the issuer. SANs are not supported.
