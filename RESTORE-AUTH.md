# Restore original signup/sign-in behavior

This build restores the original member/admin username + password + signup-code flow and the original parent anonymous-code flow.

The known parent-calendar `escHtml` bug is **not** reintroduced; the original parent authentication flow is restored while the existing calendar escaping fix remains.

For an existing Supabase project, run `rollback-auth-hardening.sql` once in SQL Editor. It rolls back migrations 6–7 while preserving the announcement feature from migration 5.

Then in Supabase Authentication settings:
- Email provider: ON
- Confirm email: OFF
- Anonymous sign-ins: ON

Finally set the codes in SQL Editor with `public.set_signup_code(...)` as shown at the bottom of the rollback script.
