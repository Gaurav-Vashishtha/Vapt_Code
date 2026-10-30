import React from 'react';
import I18n from "../i18n-lang";

const SuccessMessage = () => {
    return (
      <div className='codk-otpw-verified-proceed'>
      {I18n.t("success_message.phone_number_verified_proceed_to_checkout")}
  </div>
    );
  };

  export default SuccessMessage;