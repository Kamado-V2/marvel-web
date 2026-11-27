# MarvelVault

An unofficial fan guide to Marvel movies, television series and web shows.

## Marvel series

The series guide is searchable and filterable by live action, animation, and
web/documentary productions. It presents entries in release-year order.

The hero displays a live countdown to the listed U.S. release date for
*Avengers: Doomsday*.

## Movie posters

Movie covers load poster thumbnails on demand from Wikipedia and link to the
Wikipedia source article in each movie's details. Poster links are configured
directly in the page, so no Wikipedia search is needed while browsing. An
internet connection is required; posters that are unavailable keep the
existing color cover.

## Community polls

Community accounts, shared polls, voting, and poll media use Supabase. The rest
of the movie guide works without a Supabase project.

1. Create a Supabase project.
2. In its SQL Editor, run the contents of `supabase-community.sql`.
3. Copy the project's **Project URL** and **anon/public key** from Project
   Settings → API into `url` and `anonKey` in `assets/community-config.js`.
   The anon/public key is intended for browser use; never put a service-role
   key in this file.
4. In Authentication → URL Configuration, set the site URL to your deployed
   site and add that URL to the allowed redirect URLs. Configure email sign-up
   and confirmation to match your preference.
5. Deploy the updated site. Visitors can browse polls without an account;
   creating polls and voting require a confirmed, signed-in account. Each
   account gets a random fan nickname, and every twentieth account is assigned
   a randomly chosen Avengers hero nickname. Polls display that nickname
   instead of the account email. Each account can vote once per poll. Uploaded
   poll media is public and cannot contain private content.

War Polls are two-contender matchups; Fan Polls allow 2-6 custom answers.
Signed-in users can report a poll once for moderator review. Reports are private
to the database owner and must be reviewed in the Supabase dashboard; the site
does not include a moderator console. If the community database is already set
up, run the updated SQL file again to add War Poll types and report storage.
If only image/video uploads are missing, copy the standalone **MEDIA STORAGE
FIX** block at the top of `supabase-community.sql` into Supabase SQL Editor and
run that block; its final query confirms the bucket was created.
