import React, { useState, useEffect } from 'react';
import queryString from 'query-string';

export const useQueryString = (key, defaultVal) => {
  const [result, setResult] = useState(queryString.parse(location.search));
  const parsed = queryString.parse(location.search);
  useEffect(() => {
    setResult(queryString.parse(location.search));
  }, [location.search]);
  return result[key] || defaultVal;
};

export default useQueryString;