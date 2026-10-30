// Polyfill for Object.fromEntries to support older browsers
// Object.fromEntries was introduced in ES2019 and may not be available in older browsers

if (!Object.fromEntries) {
  Object.fromEntries = function (iter) {
    const obj = {};
    if (iter != null) {
      if (typeof iter[Symbol.iterator] === "function") {
        // Handle iterables
        const iterator = iter[Symbol.iterator]();
        let next = iterator.next();
        while (!next.done) {
          const [key, value] = next.value;
          obj[key] = value;
          next = iterator.next();
        }
      } else if (Array.isArray(iter)) {
        // Handle arrays (fallback for older environments)
        for (let i = 0; i < iter.length; i++) {
          const [key, value] = iter[i];
          obj[key] = value;
        }
      }
    }
    return obj;
  };
}

export default {};
