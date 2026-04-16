-- Storage buckets for agent media references (visual_ref, audio_ref in observations)
-- Runs against the main Supabase database (public schema)

BEGIN;

-- Create buckets if they don't exist
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES
    ('agent-visual', 'agent-visual', false, 10485760, ARRAY['image/jpeg', 'image/png', 'image/webp']),
    ('agent-audio', 'agent-audio', false, 20971520, ARRAY['audio/webm', 'audio/ogg', 'audio/mp4', 'audio/wav'])
ON CONFLICT (id) DO NOTHING;

-- RLS is already enabled on storage.objects by default in Supabase.
-- Policies: authenticated users upload/read within their own user_id prefix.
-- Agent role uploads/reads for the delegated user's prefix.

-- Authenticated user: upload to own prefix (bucket/user_id/*)
CREATE POLICY storage_agent_visual_user_insert ON storage.objects
    FOR INSERT TO authenticated
    WITH CHECK (
        bucket_id = 'agent-visual'
        AND (storage.foldername(name))[1] = auth.uid()::text
    );

CREATE POLICY storage_agent_audio_user_insert ON storage.objects
    FOR INSERT TO authenticated
    WITH CHECK (
        bucket_id = 'agent-audio'
        AND (storage.foldername(name))[1] = auth.uid()::text
    );

-- Authenticated user: read own files
CREATE POLICY storage_agent_visual_user_select ON storage.objects
    FOR SELECT TO authenticated
    USING (
        bucket_id = 'agent-visual'
        AND (storage.foldername(name))[1] = auth.uid()::text
    );

CREATE POLICY storage_agent_audio_user_select ON storage.objects
    FOR SELECT TO authenticated
    USING (
        bucket_id = 'agent-audio'
        AND (storage.foldername(name))[1] = auth.uid()::text
    );

-- Agent role: upload to delegated user's prefix
CREATE POLICY storage_agent_visual_agent_insert ON storage.objects
    FOR INSERT TO authenticated
    WITH CHECK (
        bucket_id = 'agent-visual'
        AND current_setting('request.jwt.claims', true)::jsonb->>'role' = 'agent'
        AND (storage.foldername(name))[1] = (current_setting('request.jwt.claims', true)::jsonb->>'delegated_for')
    );

CREATE POLICY storage_agent_audio_agent_insert ON storage.objects
    FOR INSERT TO authenticated
    WITH CHECK (
        bucket_id = 'agent-audio'
        AND current_setting('request.jwt.claims', true)::jsonb->>'role' = 'agent'
        AND (storage.foldername(name))[1] = (current_setting('request.jwt.claims', true)::jsonb->>'delegated_for')
    );

-- Agent role: read delegated user's files
CREATE POLICY storage_agent_visual_agent_select ON storage.objects
    FOR SELECT TO authenticated
    USING (
        bucket_id = 'agent-visual'
        AND current_setting('request.jwt.claims', true)::jsonb->>'role' = 'agent'
        AND (storage.foldername(name))[1] = (current_setting('request.jwt.claims', true)::jsonb->>'delegated_for')
    );

CREATE POLICY storage_agent_audio_agent_select ON storage.objects
    FOR SELECT TO authenticated
    USING (
        bucket_id = 'agent-audio'
        AND current_setting('request.jwt.claims', true)::jsonb->>'role' = 'agent'
        AND (storage.foldername(name))[1] = (current_setting('request.jwt.claims', true)::jsonb->>'delegated_for')
    );

COMMIT;
