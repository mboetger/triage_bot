# Triage Bot

A high-performance, single-page Jaspr web application designed to instantly verify the triage status of GitHub issues in the `mboetger/flutter` repository.

## Features

- **Dynamic Branch Resolution**: Instantly queries the GitHub Git database (`matching-refs` API) to find all branches starting with `triage-issue-<ISSUE_ID>` (such as `triage-issue-123`, `triage-issue-123-2`, etc.).
- **Drift-Free Commit Comparison**: Calculates the exact merge base commit SHA against upstream `flutter/flutter:master` to prevent branch drift from stale fork branches. It generates a pristine compare page (`<base_sha>...<branch>`) displaying only the commits added to the triage branch.
- **Smart Navigation**: Automatically directs the browser to the comparison page when exactly one branch is found. When multiple branches match, it presents a clean stack of result cards for easy selection.
- **Premium Aesthetics**: Built with a rich, glassmorphic dark mode UI, smooth gradient accents, micro-animations, and modern typography (`Outfit` and `Inter` from Google Fonts).

## Running the Project

Ensure you have Dart and Jaspr installed, then start the development server using `jaspr serve`:

```bash
jaspr serve
```

The development server will be available at `http://localhost:8080`.

## Building the Project

To build the web application for production deployment, run:

```bash
jaspr build
```

The compiled output will be located inside the `build/jaspr/` directory.
