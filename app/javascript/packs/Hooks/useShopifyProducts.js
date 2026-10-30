// import { useEffect, useState, useCallback } from 'react'
// import useApi from './useApi'
// import useInfiniteLoader from 'react-use-infinite-loader'

// const useShopifyProducts = (query) => {
//   const [data, setData] = useState([])
//   const [page, setPage] = useState(1)

//   const [{ data: apiData, loading, error }, refetch] = useApi({
//     url: '/shopify_products',
//     params: {
//       query,
//       page
//     }
//   })

//   useEffect(() => {
//     page !== 1 && setPage(1)
//     data?.length > 0 && setData([])
//   }, [query, setData])

//   const loadMore = () => {
//     setPage(p => p + 1)
//   }

//   useEffect(() => {
//     if (apiData?.data?.length > 0) {
//       setData(d => {
//         return d.concat(apiData.data)
//       })
//     }
//   }, [apiData, setData])

//   const { loaderRef } = useInfiniteLoader({
//     loadMore,
//     canLoadMore: !loading && apiData?.pagy?.page !== apiData?.pagy?.last
//   })

//   const resetAndRefetch = useCallback(() => {
//     setPage(1)
//     setData([])
//     refetch()
//   }, [setPage, setData, refetch])

//   return [{ data, loading, error }, resetAndRefetch, loaderRef]
// }

// export default useShopifyProducts
