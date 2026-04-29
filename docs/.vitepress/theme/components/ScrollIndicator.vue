<template>
  <div class="scroll-indicator">
    <span class="scroll-indicator__arrow">↓</span>
    <span class="scroll-indicator__text">Scroll for more</span>
  </div>
</template>

<style scoped>
.scroll-indicator {
  position: relative;
  margin: 4rem auto 0;
  min-height: 3rem;
  
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 0.5em;
  
  width: 100%;
  max-width: max-content;
  padding: 0em 1.5em;
  
  background-color: var(--vp-c-bg);
  border: 1px solid var(--vp-c-divider);
  border-radius: 1.5rem;
  font-weight: 700;
  font-size: clamp(0.4rem, 2vw, 1rem);
  overflow: hidden;
  
  animation: scroll-entry 0.5s ease 1s both;
}

.scroll-indicator::after {
  content: "";
  position: absolute;
  top: 0;
  bottom: 0;
  left: -200%;
  right: -200%;
  height: 100%;
  background: linear-gradient(
    to right, 
    var(--vp-c-bg) 40%, 
    var(--vp-c-brand-1) 48%,
    var(--vp-c-brand-1) 52%,
    var(--vp-c-bg) 60%
  );
  opacity: 0.15;
  animation: scroll-shimmer 3s linear infinite;
  pointer-events: none;
}

.scroll-indicator__arrow {
  display: inline-block;
  animation: scroll-bounce 1.5s ease-in-out infinite;
  font-size: 1.2em;
}

.scroll-indicator__text {
  position: relative;
  z-index: 1;
}

@keyframes scroll-entry {
  0% {
    opacity: 0;
    transform: translateY(1rem);
  }
  100% {
    opacity: 1;
    transform: translateY(0);
  }
}

@keyframes scroll-bounce {
  0%, 100% {
    transform: translateY(-0.3rem);
  }
  50% {
    transform: translateY(0.3rem);
  }
}

@keyframes scroll-shimmer {
  0% {
    transform: translateX(-25%);
  }
  100% {
    transform: translateX(25%);
  }
}

@media (max-width: 768px) {
  .scroll-indicator {
    font-size: 0.85rem;
    padding: 0.5em 0.5em;
  }
}
</style>