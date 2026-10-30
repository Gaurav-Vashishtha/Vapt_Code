import { useState, useEffect, useContext } from "react";
import Api from "../../Services/Api";
import { StoreContext } from "../../Context/Store";

const cache = new Map();

function fetchFastDashboard(shopId, days) {
  const key = `${shopId}:${days}`;
  if (!cache.has(key)) {
    const promise = Api.get(
      `/analytics/fast_dashboard?shop_id=${shopId}&days=${days}`,
    )
      .then((response) => response.data)
      .catch((error) => {
        cache.delete(key);
        throw error;
      });
    cache.set(key, promise);
  }
  return cache.get(key);
}

export function resetFastDashboardCache() {
  cache.clear();
}

export default function useFastDashboard(days = 30) {
  const {
    shop: [shop],
  } = useContext(StoreContext);
  const shopId = shop?.id;

  const [state, setState] = useState({
    data: null,
    loading: true,
    error: null,
  });

  useEffect(() => {
    if (!shopId) return undefined;
    let mounted = true;
    setState({ data: null, loading: true, error: null });
    fetchFastDashboard(shopId, days)
      .then((data) => {
        if (mounted) setState({ data, loading: false, error: null });
      })
      .catch((error) => {
        if (mounted) setState({ data: null, loading: false, error });
      });
    return () => {
      mounted = false;
    };
  }, [shopId, days]);

  return state;
}
