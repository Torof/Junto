/** @type {import('next').NextConfig} */
// Security headers (audit CL-3). No full Content-Security-Policy on purpose:
// Next inlines its bootstrap scripts, so a script policy would need nonces —
// frame-ancestors alone is safe and stops click-jacking.
const securityHeaders = [
  { key: 'X-Content-Type-Options', value: 'nosniff' },
  { key: 'Referrer-Policy', value: 'strict-origin-when-cross-origin' },
  { key: 'X-Frame-Options', value: 'DENY' },
  { key: 'Content-Security-Policy', value: "frame-ancestors 'none'" },
  { key: 'Permissions-Policy', value: 'camera=(), microphone=(), geolocation=(), payment=()' },
  { key: 'Strict-Transport-Security', value: 'max-age=63072000' },
];

const nextConfig = {
  reactStrictMode: true,
  eslint: { ignoreDuringBuilds: true },
  async headers() {
    return [{ source: '/:path*', headers: securityHeaders }];
  },
};
module.exports = nextConfig;
