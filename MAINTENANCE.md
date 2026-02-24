# Maintenance and Security

This document tracks configuration changes for development and provides instructions on how to manage security settings.

## CSRF Protection

CSRF (Cross-Site Request Forgery) protection is **ENABLED** in `backend/hospital_project/settings.py`.

### Whitelisting Origins (Ngrok, etc.)
When accessing the site through a proxy like ngrok, you must add the domain to `CSRF_TRUSTED_ORIGINS`:

1.  Open `backend/hospital_project/settings.py`.
2.  Find the `CSRF_TRUSTED_ORIGINS` list.
3.  Add your new URL:
    ```python
    CSRF_TRUSTED_ORIGINS = [
        'https://your-ngrok-url.ngrok-free.app',
    ]
    ```
4.  Save the file.

### Disabling CSRF (Not Recommended)
If you must disable it for debugging:
1.  Comment out the middleware line:
    ```python
    # 'django.middleware.csrf.CsrfViewMiddleware',
    ```

> [!CAUTION]
> Always ensure CSRF protection and proper trusted origins are configured before deploying to production.
