# Contributing to DNSClient

First off, thank you for considering a contribution! We welcome improvements to the library, but to maintain a high standard of quality, correctness, and consistency, we ask that you follow these guidelines.

## Contribution Workflow

To ensure changes are aligned with the project's goals and to avoid wasted effort, we follow a simple workflow:

1.  **Open an Issue:** Before starting significant work, please [open an issue](https://github.com/orlandos-nl/DNSClient/issues/new) to discuss your proposed change. This allows us to agree on the approach before you write any code. For small bug fixes, this may not be necessary.
2.  **Create a Pull Request:** Once the approach is agreed upon, create a Pull Request (PR). It's often helpful to create a **Draft PR** early in the process to get feedback.
3.  **Pass the Code Review:** All changes are subject to code review. Be prepared to discuss your changes and make adjustments based on feedback. The principles below form the basis of our review criteria.

## Core Principles

These are the foundational principles of our library. Adherence to them is required for all contributions.

### 1. Strict Standards Compliance

The keywords "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in [RFC 2119](https://datatracker.ietf.org/doc/html/rfc2119).

**All implementations MUST strictly adhere to the relevant IETF RFCs.**

*   When implementing a feature defined by an RFC (e.g., a new record type), you are expected to read and understand the standard.
*   Your Pull Request description **MUST** cite the specific RFC(s) and section(s) that your implementation is based on.
*   The data structures and logic **MUST** be a direct and accurate representation of the standard.

### 2. Architectural Principles

We enforce a strong **Separation of Concerns** to keep the library clean and maintainable.

*   **Data Models MUST Be Pure:** Structs representing DNS data (like `ARecord` or `AAAARecord`) **MUST** be simple, plain-data types that are a 1-to-1 mapping of the data defined in the RFC.
*   **Do Not Mix Layers:** Do not couple data models with abstractions. We create our own record types, and translate to different currency types of the ecosystem if the need exists.

### 3. API Design and Naming Conventions

Our goal is a clean, expressive, and "Swifty" API.

*   **Follow Swift API Design Guidelines:** All contributions **MUST** adhere to the official [Swift API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/).
*   **Avoid Redundant Prefixes:** Within this library, the "DNS" context is implicit. Do not prefix types with `DNS` (e.g., use `DomainName`, not `DNSName`). Let the module serve as the namespace.
*   **Strive for Clarity:** Names of types, methods, and variables **SHOULD** be clear and unambiguous.

## Code Quality and Testing

*   **Style:** All code **SHOULD** be formatted according to the Swift standard.
*   **Testing:** All contributions **MUST** be accompanied by tests.
    *   **New Features:** **MUST** include unit tests that cover the new functionality.
    *   **Bug Fixes:** **MUST** include a regression test that fails before the fix and passes after.

## Commit Messages

Please write clear and concise commit messages. The subject line **SHOULD** be in the imperative mood (e.g., "Fix: Correct ARecord data type") and briefly describe the change. The body can contain more detail if necessary.

---

By following these guidelines, you help us maintain the quality and integrity of the project. Thank you for your contribution!
