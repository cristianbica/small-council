# Authentication

Built with [authentication-zero](https://github.com/lazaronixon/authentication-zero) gem.

## Flows

### Sign Up
- Path: `GET /sign_up`
- Creates an account and first user (admin)
- Auto-logs in after registration
- Required fields: account name, account slug, email, password, password confirmation

### Sign In
- Path: `GET /sign_in`
- Validates credentials, creates session record
- Sets permanent signed cookie with session token
- Redirects to root/dashboard on success

### Sign Out
- Path: `DELETE /session/:id` or destroy own session
- Destroys session record, clears cookie

### Password Reset
- Request: `GET /identity/password_reset/new`
- Reset link with token sent via email
- Reset form: `GET /identity/password_reset/edit?sid=TOKEN`
- Tokens expire in 20 minutes

## Current Attributes

Access via `Current`:
- `Current.session` - the active session record
- `Current.user` - delegated from session (authenticated user)
- `Current.user_agent`, `Current.ip_address` - request metadata

## Session Management

Sessions stored in `sessions` table:
- `user_id` - belongs to user
- `user_agent`, `ip_address` - captured on creation
- Multiple sessions per user allowed (session list UI at `/sessions`)
- Cookie-based with `session_token` (signed, httponly, permanent)

## Protected Routes

All routes require authentication by default (`ApplicationController#authenticate`).

To skip for public routes:
```ruby
skip_before_action :authenticate, only: [:index, :show]
```

## Demo Credentials (Development)

After `bin/rails db:seed`:
- Email: `demo@example.com`
- Password: `password123`
- URL: http://localhost:3000/sign_in

## Routes Summary

| Path | Description |
|------|-------------|
| `/sign_in` | Login form |
| `/sign_up` | Registration form |
| `/sessions` | List active sessions |
| `/password/edit` | Change password (logged in) |
| `/identity/password_reset/new` | Request password reset |
| `/identity/email/edit` | Change email |
