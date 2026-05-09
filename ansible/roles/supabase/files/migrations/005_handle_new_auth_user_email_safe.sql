-- Make the auth.users insert trigger tolerant of email-only signups.
--
-- Background: handle_new_auth_user() unconditionally inserted (id, new.phone)
-- into public.users, which has phone NOT NULL. That worked while every signup
-- went through Twilio (phone was always set). Once GoTrue's email magic-link
-- flow goes live (after switching SMTP from the supabase-mail stub to Resend),
-- email-only signups arrive with new.phone IS NULL and the trigger raised
-- "null value in column phone of relation public.users violates not-null
-- constraint" — failing the auth.users insert and bubbling 500 to the client.
--
-- Fix: coalesce phone to '' on the insert (matches the existing dungeon-master
-- demo-user pattern that uses '' for unknown phone), and skip the invitations
-- backfill entirely when phone is null (nothing to match against).

create or replace function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer
as $$
begin
    insert into public.users (id, phone)
    values (new.id, coalesce(new.phone, ''));

    if new.phone is not null then
        update public.invitations
        set invited_user_id = new.id
        where public.normalize_us_phone(invited_phone)
            = public.normalize_us_phone(new.phone);
    end if;

    return new;
end;
$$;
