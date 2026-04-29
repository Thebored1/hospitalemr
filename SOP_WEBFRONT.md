# Hospital EMR - Webfront SOP

## Table of Contents
1. Application Overview
2. Login Screen
3. Signup Screen
4. Role Switcher
5. Maintenance Dashboard
6. Advisor Dashboard
7. All Tickets Screen
8. Add Ticket Screen
9. Task Detail Screen
10. Add Patient Screen
11. All Patients Screen
12. Start Trip Screen
13. Trip Dashboard Screen
14. Refer Doctor Screen
15. Add Hotel Screen
16. End Trip Screen
17. Doctor Referral Details Screen
18. Hotel Stay Details Screen
19. Success Screen
20. Widgets and Components
21. Offline Mode and Sync
22. Navigation Flow
## 1. Application Overview
### Purpose
The Hospital EMR webfront enables staff to manage maintenance, patient referrals, doctor visits, and trip workflows with offline support and camera/GPS integration.

### User Roles
- Marketing Advisor: manages trips, patient referrals, and doctor visits
- Maintenance Runner: handles facility maintenance tickets

### Technology Stack
- Frontend: Flutter (Dart)
- Backend: Django REST API
- Offline: SQLite for local storage, offline sync
\n## 2. Login Screen
### File
lib/screens/login_screen.dart
\n### Purpose
Authenticate users with phone and password; handle Remember Me, password visibility, and navigation to RoleSwitcher
\n### Buttons & Controls
| Button | Location | Action |
|---|---|---|
| Login Button | Form Card | Validates input, authenticates via API, navigates to RoleSwitcher
| Remember Me Checkbox | Form | Toggles credential storage locally
| Password Toggle | Password field | Show/hide password
