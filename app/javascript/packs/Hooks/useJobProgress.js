// import { useState } from 'react'
// import useInterval from '@use-it/interval'
// import useApi from './useApi'

// const useJobProgress = (jobId) => {
//   const [{ data, loading }, getJobProgress] = useApi({
//     url: '/jobs/status',
//     method: 'POST',
//     data: { jobId }
//   }, { manual: true })

//   const [isRunning, setIsRunning] = useState(true)

//   useInterval(() => {
//     getJobProgress().then(resp => {
//       if (
//         resp?.data?.error ||
//         resp?.data?.status === 'complete'||
//         resp?.data?.status === 'failed') {
//           setIsRunning(false)
//           return
//       }
//     })

//   }, (jobId && isRunning) ? 3000 : null)

//   return { progress: data, loading }
// }

// export default useJobProgress
