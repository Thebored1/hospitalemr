# Agent Context: Backend Architecture & Backup

This document provides context for any AI agent or developer assessing the `hospitalemr` project, specifically focusing on the backend component.

## Backup File
A full backup of the backend directory is available at:
`backend_backup.zip` (located in the project root directory).
You can extract or reference this file if you need to recover the backend code to a known, stable state.

## Backend Overview
The backend is a monolithic Django REST API application located in the `backend/` directory. It uses Django 6.0.1 and Django REST Framework.

### Key Applications
- **`hospital_project`**: The main configuration module. It handles routing (`urls.py`), settings (`settings.py`), and WSGI/ASGI application definitions.
- **`core`**: Contains the primary domain models and API endpoints for the core application (e.g., users, core records).
- **`portal`**: Likely the web-based administrative portal or dashboard logic and views. Contains a `templates/` directory.

### Environment & Database
- The project is configured with `django-cors-headers` to support Flutter clients (mobile and web).
- Uses `gunicorn` and `whitenoise` indicating it's configured for production WSGI server deployment and static file serving.
- The default database is SQLite (`db.sqlite3` in `backend/`), but it holds drivers for PostgreSQL (`psycopg`), suggesting PG is intended for production.
- Use `backend/venv/` as the virtual environment if running python scripts.

### Flutter Client Interaction
The primary client is a Flutter application (`lib/`). The Flutter client communicates via REST APIs defined in the `core` django application and stores a local session using `shared_preferences`. Data syncing handles offline capability through a `SyncService`.

**Note to Agents**: When modifying this project, avoid accidentally introducing backward-incompatible API changes to the `core` app, as the mobile client heavily relies on the existing contracts.
