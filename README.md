# Triage Bot

A high-performance, single-page Jaspr web application designed to instantly verify the triage status of GitHub issues in the `mboetger/flutter` repository.

## Features

- **Dynamic Branch Resolution**: Instantly queries the GitHub Git database (`matching-refs` API) to find all branches starting with `triage-issue-<ISSUE_ID>` (such as `triage-issue-123`, `triage-issue-123-2`, etc.).
- **Drift-Free Commit Comparison**: Calculates the exact merge base commit SHA against upstream `flutter/flutter:master` to prevent branch drift from stale fork branches. It generates a pristine compare page (`<base_sha>...<branch>`) displaying only the commits added to the triage branch.
- **Explicit Navigation**: Displays beautiful result cards with direct links to launch the pristine commit comparison page in a new window (`target="_blank"`).
- **Premium Aesthetics**: Built with a rich, glassmorphic dark mode UI, smooth gradient accents, micro-animations, and modern typography (`Outfit` and `Inter` from Google Fonts).
- **Firebase Backend**: A scheduled Cloud Function automatically processes triage branches daily, diffs them against `master` to track file modifications, and aggregates repository-wide analytics into a secure, internet-isolated Firestore database. The frontend fetches this live data via a serverless HTTPS endpoint to display top changed files and branch volume statistics.

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

## Firebase Backend Deployment

The project is configured with GitHub Actions to automatically deploy both the Jaspr frontend and the Firebase Backend (Functions and Firestore rules) upon pushing to the `main` branch. 

To build and deploy the backend manually:

```bash
cd functions
npm ci
npm run build
cd ..
npx firebase-tools deploy --only functions,firestore,hosting
```
