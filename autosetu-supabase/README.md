# AUTOSETU (GitHub Pages + Supabase, 100% free tier)
## A. Database (5 min)
1. supabase.com -> sign up -> New project (save the DB password).
2. Authentication -> Providers -> Email -> turn OFF "Confirm email" (easier testing).
3. SQL Editor -> New query -> paste all of `supabase.sql` -> Run.
4. Project Settings -> API: copy the Project URL and the `anon public` key.
## B. Website
5. Open `index.html`, replace PASTE_PROJECT_URL and PASTE_ANON_PUBLIC_KEY. (Never use the service_role key.)
6. GitHub -> New repository -> upload `index.html` -> Settings -> Pages -> Deploy from branch `main` / root. Your site appears at https://YOURNAME.github.io/REPO/
7. Supabase -> Authentication -> URL Configuration -> set Site URL to that address.
## C. First admin (secure)
8. Register normally on the site with your email. Then in Supabase SQL Editor run:
   update profiles set role='admin', verified=true where id=(select id from auth.users where email='YOUR@EMAIL');
9. Logout/login: you see the admin panel.
## D. Test
Register a driver + a passenger (two browsers). Admin approves the driver. Driver GO ONLINE, passenger requests, driver ACCEPT -> ARRIVED -> START -> COMPLETE, passenger rates.
