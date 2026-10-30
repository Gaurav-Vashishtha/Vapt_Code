import React, { useState } from "react";
import ClipLoader from "react-spinners/ClipLoader";
import MoonLoader from "react-spinners/MoonLoader";
const override = { borderWidth: "8px" };

function LoadingLottiePlayer() {
  let [loading, setLoading] = useState(true);
  let [color, setColor] = useState("#06ab3e");

  return (
    <div className="sweet-loading">
      <ClipLoader
        color={color}
        loading={loading}
        cssOverride={override}
        size={300}
        speedMultiplier={0.3}
        aria-label="Loading Spinner"
        data-testid="loader"
      />
    </div>
  );
}

export default LoadingLottiePlayer;
