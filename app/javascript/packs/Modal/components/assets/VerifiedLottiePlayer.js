import React, { useEffect } from "react";

const VerifiedLottiePlayer = () => {
  useEffect(() => {
    // Dynamically import the dotlottie-player module
    const loadLottiePlayer = async () => {
      const script = document.createElement("script");
      script.src =
        "https://unpkg.com/@dotlottie/player-component@latest/dist/dotlottie-player.mjs";
      script.type = "module";
      document.body.appendChild(script);
    };

    loadLottiePlayer();
  }, []);

  return (
    <div
      style={{
        textAlign: "center",
        padding: "20px",
        display: "flex",
        justifyContent: "center",
        background: "transparent",
      }}
    >
      <dotlottie-player
        src="https://lottie.host/f4babdd0-3e11-4436-886f-0d66bbff8dbc/2S55ulqq32.json"
        background="transparent"
        speed="1.8"
        style={{ width: "300px", height: "300px" }}
        loop
        autoplay
      ></dotlottie-player>
    </div>
  );
};

export default VerifiedLottiePlayer;
