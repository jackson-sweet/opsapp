// OPS/Network/Supabase/SupabaseConfig.swift
import Foundation

enum SupabaseConfig {
    /// Supabase project URL
    static let url = URL(string: "https://ijeekuhbatykdomumfjx.supabase.co")!

    /// Supabase anon key — safe to embed in mobile clients.
    /// Data is protected by Row Level Security policies, not by keeping this key secret.
    static let anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImlqZWVrdWhiYXR5a2RvbXVtZmp4Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzEyNzM2MTgsImV4cCI6MjA4Njg0OTYxOH0.pXYn9WRpVkWSJg2vHw2fjw8RsAmytnRGwEjb2Jwrn-c"
}
