# marvel-web is all about to make people enjoy and know more abut marvel movies

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
