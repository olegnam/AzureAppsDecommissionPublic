# Security Policy

## Important warning

This repository contains automation that can delete Azure resources, including:

- Azure Web Apps
- Private Endpoints
- Network Interfaces

This is destructive automation and should only be used in controlled, validated environments.

## Safety recommendations

- Run in a non-production subscription first
- Use dry-run mode before any delete operation
- Validate the target resource group and app list before execution
- Ensure you are connected to the correct Azure subscription
- Never commit `apps-to-delete.csv` or generated output files
- Review all planned deletions before using `-Delete`

## Reporting a security issue

Please do not disclose sensitive Azure identifiers, credentials, or environment details in a public issue.

If you discover a security issue or a dangerous behavior in this project, report it privately through the repository owner or GitHub security reporting flow.
