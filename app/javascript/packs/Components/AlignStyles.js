const GetAlignStyles = (setting, isPreview = false) => {
  const styles = {
    position: isPreview ? 'absolute' : 'fixed',
    zIndex: isPreview ? 9 : 9999999999,
    paddingBottom: isPreview ? 5 : 100
  };
  if (!setting.status && !isPreview) {
    styles.display = 'none';
  }
  return styles;
}

export default GetAlignStyles;