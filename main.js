const aboutPages = ['about-org', 'about-first', 'student-leaders', 'mentors'];
const robotDetailPages = ['robot-2026a', 'robot-2026b', 'robot-2025', 'robot-2024', 'robot-2023', 'robot-2022'];
const mediaPages = ['media-2026', 'media-2025', 'media-2024', 'media-2023', 'media-2022'];
const MOBILE_NAV_BREAKPOINT = 900;
let activeRobotsTeam = '3006';

function isMobileNavViewport() {
  return window.matchMedia(`(max-width: ${MOBILE_NAV_BREAKPOINT}px)`).matches;
}

function setMobileNavOpen(isOpen) {
  const navMenu = document.getElementById('nav-menu');
  const navToggle = document.getElementById('nav-toggle');
  const navScrim = document.getElementById('nav-scrim');

  if (!navMenu || !navToggle || !navScrim) return;

  navMenu.classList.toggle('open', isOpen);
  navToggle.classList.toggle('active', isOpen);
  navScrim.classList.toggle('active', isOpen);
  navToggle.setAttribute('aria-expanded', isOpen ? 'true' : 'false');
  navToggle.setAttribute('aria-label', isOpen ? 'Close menu' : 'Open menu');
  document.body.classList.toggle('nav-open', isOpen);
}

function closeMobileNav() {
  setMobileNavOpen(false);
}

function closeAllNavDropdowns() {
  document.querySelectorAll('.nav-right .dropdown.open').forEach(dropdown => {
    dropdown.classList.remove('open');
  });
}

function handleMobileDropdownToggle(event) {
  if (!isMobileNavViewport()) return;

  const dropdown = event.currentTarget.closest('.dropdown');
  if (!dropdown) return;

  event.preventDefault();
  const shouldOpen = !dropdown.classList.contains('open');

  closeAllNavDropdowns();
  if (shouldOpen) dropdown.classList.add('open');
}

function initializeMobileNav() {
  const navToggle = document.getElementById('nav-toggle');
  const navScrim = document.getElementById('nav-scrim');
  const dropdownTriggers = document.querySelectorAll('.nav-right .dropdown-trigger');

  if (!navToggle || !navScrim) return;

  navToggle.addEventListener('click', () => {
    const isOpen = document.body.classList.contains('nav-open');
    setMobileNavOpen(!isOpen);
  });

  navScrim.addEventListener('click', () => {
    closeAllNavDropdowns();
    closeMobileNav();
  });

  dropdownTriggers.forEach(trigger => {
    trigger.addEventListener('click', handleMobileDropdownToggle);
  });

  window.addEventListener('resize', () => {
    if (!isMobileNavViewport()) {
      closeAllNavDropdowns();
      closeMobileNav();
    }
  });

  document.addEventListener('keydown', event => {
    if (event.key === 'Escape') {
      closeAllNavDropdowns();
      closeMobileNav();
    }
  });
}

function setRobotsTeam(team) {
  activeRobotsTeam = team;

  const list3006 = document.getElementById('robots-list-3006');
  const list2726 = document.getElementById('robots-list-2726');
  const btn3006 = document.getElementById('robots-team-3006');
  const btn2726 = document.getElementById('robots-team-2726');

  if (!list3006 || !list2726 || !btn3006 || !btn2726) return;

  const show3006 = team === '3006';
  list3006.classList.toggle('hidden', !show3006);
  list2726.classList.toggle('hidden', show3006);

  btn3006.classList.toggle('active', show3006);
  btn2726.classList.toggle('active', !show3006);
  btn3006.setAttribute('aria-selected', show3006 ? 'true' : 'false');
  btn2726.setAttribute('aria-selected', show3006 ? 'false' : 'true');
}

function renderPage(id, scrollBehavior = 'smooth') {
  document.querySelectorAll('.page').forEach(p => p.classList.remove('active'));
  const page = document.getElementById(id);
  if (page) page.classList.add('active');

  if (id === 'robots') setRobotsTeam(activeRobotsTeam);

  document.querySelectorAll('.nav-right a, .nav-right .dropdown-trigger').forEach(a => a.classList.remove('active'));

  let navTarget = id;
  if (aboutPages.includes(id)) navTarget = 'about';
  else if (robotDetailPages.includes(id)) navTarget = 'robots';
  else if (mediaPages.includes(id)) navTarget = 'media';

  const navEl = document.getElementById('nav-' + navTarget);
  if (navEl) navEl.classList.add('active');

  window.scrollTo({ top: 0, behavior: scrollBehavior });
}

function getRoutePageId() {
  const pageId = window.location.hash.replace('#', '').trim();
  if (!pageId) return 'home';
  if (pageId === 'media') return 'media-2026';
  return document.getElementById(pageId) ? pageId : 'home';
}

function showPage(id) {
  closeAllNavDropdowns();
  closeMobileNav();

  const targetId = document.getElementById(id) ? id : 'home';
  const targetHash = '#' + targetId;

  if (window.location.hash !== targetHash) {
    window.location.hash = targetHash;
    return;
  }

  renderPage(targetId);
}

async function submitSponsorForm() {
  const company = document.getElementById('s-company').value.trim();
  const name    = document.getElementById('s-name').value.trim();
  const email   = document.getElementById('s-email').value.trim();
  const phoneEl = document.getElementById('s-phone');
  const messageEl = document.getElementById('s-message');
  const submitBtn = document.querySelector('#sponsor-form-wrap .btn.btn-primary');
  const phone = phoneEl ? phoneEl.value.trim() : '';
  const message = messageEl ? messageEl.value.trim() : '';

  if (!company || !name || !email) {
    alert('Please fill in the required fields (Company, Name, and Email).');
    return;
  }

  if (submitBtn) {
    submitBtn.disabled = true;
    submitBtn.textContent = 'Sending...';
  }

  try {
    const response = await fetch('https://formsubmit.co/ajax/whsred3006@gmail.com', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json'
      },
      body: JSON.stringify({
        _subject: `Sponsor Inquiry - ${company}`,
        company,
        contactName: name,
        email,
        phone: phone || 'Not provided',
        message: message || 'No message provided.',
        _captcha: 'false'
      })
    });

    if (!response.ok) {
      throw new Error('Request failed');
    }

    document.getElementById('sponsor-form-wrap').style.display = 'none';
    document.getElementById('form-submitted').style.display = 'block';
  } catch (error) {
    alert('We could not send your inquiry right now. Please try again in a moment.');
  } finally {
    if (submitBtn) {
      submitBtn.disabled = false;
      submitBtn.textContent = 'Submit Inquiry';
    }
  }
}

function startHomepageBackgroundRotation() {
  const heroImage = document.querySelector('.hero-img');
  if (!heroImage) return;

  const rotationImages = [
    'images/homepage/2026utah.jpg',
    'images/homepage/2026idaho.jpeg',
    'images/homepage/2025worlds.JPG',
    'images/homepage/gustavidaho.JPG',
    'images/homepage/celebrationcolorado.png',
    'images/homepage/hilbertworlds.jpg',
    'images/homepage/2024colorado.JPG'
  ];

  rotationImages.forEach(src => {
    const img = new Image();
    img.src = src;
  });

  let currentIndex = 0;
  heroImage.src = rotationImages[currentIndex];
  heroImage.style.opacity = '0.45';

  setInterval(() => {
    heroImage.style.opacity = '0';

    setTimeout(() => {
      currentIndex = (currentIndex + 1) % rotationImages.length;
      heroImage.src = rotationImages[currentIndex];
      heroImage.style.opacity = '0.45';
    }, 1000);
  }, 8000);
}

window.addEventListener('hashchange', () => {
  renderPage(getRoutePageId(), 'auto');
});

window.addEventListener('DOMContentLoaded', () => {
  initializeMobileNav();
  renderPage(getRoutePageId(), 'auto');
  startHomepageBackgroundRotation();
});
