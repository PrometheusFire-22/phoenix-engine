# Project Chronos Architecture

Here is the system context diagram:

```mermaid
graph TD
    subgraph "External Systems"
        direction LR
        fred_api[🏦 FRED API]
        valet_api[🏦 Valet API]
    end
    
    subgraph "Project Chronos"
        platform[<b style='font-size:1.2em'>Project Chronos</b><br/>Multi-modal economic data platform.]
    end

    subgraph "Users"
        analyst[👩‍💻 Financial Analyst]
    end

    analyst -- "Uses" --> platform
    platform -- "Consumes data from" --> fred_api
    platform -- "Consumes data from" --> valet_api
