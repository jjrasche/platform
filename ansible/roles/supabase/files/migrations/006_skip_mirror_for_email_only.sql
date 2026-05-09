-- 006_skip_mirror_for_email_only.sql
-- Surgical fix to the public.handle_new_auth_user trigger from event-planner.
--
-- public.users is a phone-routable identity mirror (used by SMS workflows like
-- Twilio Verify + the public.invitations join). Email-only signups are NOT
-- phone-routable, so they don't belong in the mirror. Original trigger
-- inserted (id, NULL) and broke on the NOT NULL constraint, blocking ALL
-- email signups across every tenant. Migration 005 coalesced NULL → '' but
-- '' is unique-constrained so it only worked for the first email-only user.
--
-- Real fix: trigger early-returns when phone is null. No public.users schema
-- change. No impact on phone-signup flows. Discovered while provisioning a
-- dungeon-master smoke user; ratified by event-planner ownership review.
--
-- After this lands, the disable/re-enable workaround in
-- reference_event_planner_signup_trigger.md is obsolete — drop it.

create or replace function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    if new.phone is null then
        return new;
    end if;

    insert into public.users (id, phone) values (new.id, new.phone);

    update public.invitations
    set invited_user_id = new.id
    where public.normalize_us_phone(invited_phone)
        = public.normalize_us_phone(new.phone);

    return new;
end;
$$;
