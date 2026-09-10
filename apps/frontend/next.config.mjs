/** @type {import('next').NextConfig} */
const nextConfig = {
  output: 'standalone',
  reactStrictMode: true,
  async rewrites() {
    const api = process.env.NEXT_PUBLIC_API_URL || 'http://samba-api:8000';
    return [
      { source: '/api/:path*', destination: `${api}/:path*` }
    ];
  }
};
export default nextConfig;
