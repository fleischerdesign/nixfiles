_final: prev: {
  bottles = prev.bottles.override {
    removeWarningPopup = true;
  };
}
