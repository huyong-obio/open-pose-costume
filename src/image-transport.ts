export function atomflowRoute(endpoint: string): 'site' | 'api' | null {
  const url = new URL(endpoint);
  return url.pathname === '/v1/images/edits' && !url.search && !url.hash
    ? url.origin === 'https://atomflow.vip'
      ? 'site'
      : url.origin === 'https://api.atomflow.vip'
        ? 'api'
        : null
    : null;
}

export function isVolcengineArkEndpoint(endpoint: string): boolean {
  try {
    const url = new URL(endpoint);
    const host = url.hostname.toLowerCase();
    const arkHost =
      host === 'ark.cn-beijing.volces.com' ||
      host.endsWith('.volces.com') ||
      host.endsWith('.volcengineapi.com');
    return (
      arkHost && url.pathname === '/api/v3/images/generations' && !url.search && !url.hash
    );
  } catch {
    return false;
  }
}

/** Same-origin Volcengine Ark proxy path used by Vite dev and Docker nginx. */
export function volcengineProxyPath(): string {
  return '/opc-proxy/ark/api/v3/images/generations';
}

/** Route only exact Atomflow / Volcengine endpoints through a fixed-destination transport. */
export function imageRequestEndpoint(
  endpoint: string,
  development: boolean,
  productionProxy = '',
): string {
  const route = atomflowRoute(endpoint);
  if (route) {
    if (development) return `/__opc-image/${route}/v1/images/edits`;
    if (!productionProxy.trim()) return endpoint;
    const proxy = new URL(productionProxy.trim());
    if (
      proxy.protocol !== 'https:' ||
      proxy.username ||
      proxy.password ||
      proxy.search ||
      proxy.hash
    )
      throw new Error('invalidProxyEndpoint');
    const pathname = proxy.pathname.replace(/\/+$/, '');
    return `${proxy.origin}${pathname}/${route}/v1/images/edits`;
  }

  if (isVolcengineArkEndpoint(endpoint)) {
    if (development) return volcengineProxyPath();
    // Prefer same-origin nginx proxy in the browser to attach Authorization and avoid CORS.
    if (typeof location !== 'undefined' && /^https?:$/.test(location.protocol))
      return `${location.origin}${volcengineProxyPath()}`;
  }

  return endpoint;
}
