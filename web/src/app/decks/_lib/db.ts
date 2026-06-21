"use client";

import { createClient } from "@/lib/supabase/client";

// Shared browser Supabase client for all deck dashboard components.
export const supabase = createClient();
