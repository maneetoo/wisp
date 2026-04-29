<template>
  <div class="next-steps-section">
    <div class="container">
      <h2 class="title">{{ title }}</h2>
      <p class="description">{{ description }}</p>
      <div class="links">
        <a
          v-for="link in links"
          :key="link.href"
          :href="withBase(link.href)"
          class="link-card"
        >
          <div class="content">
            <h3>{{ link.title }}</h3>
            <p>{{ link.description }}</p>
          </div>
          <div class="arrow">→</div>
        </a>
      </div>
    </div>
  </div>
</template>

<script setup>
import { withBase } from 'vitepress'

defineProps({
  title: {
    type: String,
    default: 'Ready to dive in?'
  },
  description: {
    type: String,
    default: 'Start learning Wisp with our comprehensive guides'
  },
  links: {
    type: Array,
    default: () => []
  }
})
</script>

<style scoped>
.next-steps-section {
  padding: 6rem 2rem;
  background: transparent;
}

.container {
  max-width: 1200px;
  margin: 0 auto;
  text-align: center;
  background: var(--vp-c-bg);
  border-radius: 16px;
  padding: 4rem 2rem;
  box-shadow: 0 14px 12px rgba(10, 8, 47, 0.05);
}

.title {
  font-size: 2.5rem;
  font-weight: 700;
  margin: 0 0 1rem 0;
  padding: 0;
  color: var(--vp-c-text-1);

  border-top: none;
  padding-top: 0;
}

.description {
  font-size: 1.2rem;
  color: var(--vp-c-text-2);
  margin: 0 0 3.5rem 0;
  padding: 0;
}

.links {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
  gap: 2rem;
  text-align: left;
  padding: 0;
  margin: 0;
}

.link-card {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 1.5rem;
  padding: 2rem;
  background: var(--vp-c-bg);
  border: 1px solid var(--vp-c-divider);
  border-radius: 12px;
  text-decoration: none;
  transition: all 0.3s ease;
  cursor: pointer;
}

.link-card:hover {
  border-color: var(--vp-c-brand-1);
  transform: translateY(-6px);
  box-shadow: 0 12px 32px rgba(0, 38, 255, 0.15);
}

.content {
  flex-grow: 1;
  padding: 0;
  margin: 0;
}

.content h3 {
  font-size: 1.3rem;
  font-weight: 700;
  margin: 0 0 0.5rem 0;
  padding: 0;
  color: var(--vp-c-text-1);
  line-height: 1.3;
}

.content p {
  font-size: 0.95rem;
  color: var(--vp-c-text-2);
  margin: 0;
  padding: 0;
  line-height: 1.6;
}

.arrow {
  font-size: 1.8rem;
  color: var(--vp-c-brand-1);
  flex-shrink: 0;
  transition: transform 0.3s ease;
  font-weight: 700;
}

.link-card:hover .arrow {
  transform: translateX(6px);
}

@media (max-width: 768px) {
  .next-steps-section {
    padding: 4rem 1rem;
  }

  .title {
    font-size: 2rem;
  }

  .description {
    font-size: 1rem;
    margin-bottom: 2.5rem;
  }

  .links {
    grid-template-columns: 1fr;
    gap: 1.5rem;
  }

  .link-card {
    padding: 1.5rem;
  }

  .content h3 {
    font-size: 1.1rem;
  }
}

@media (max-width: 480px) {
  .next-steps-section {
    padding: 3rem 0.5rem;
  }

  .title {
    font-size: 1.75rem;
  }

  .link-card {
    text-align: center;
  }

  .arrow {
    display: none;
  }
}
</style>