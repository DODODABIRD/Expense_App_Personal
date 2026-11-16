let alertTimer = null;

function showAlert(message) {
  const alert = document.getElementById('alert');
  alert.textContent = message;
  alert.className = 'status error visible';
  if (alertTimer) clearTimeout(alertTimer);
  alertTimer = setTimeout(function () {
    alert.className = 'status error';
  }, 5000);
}

function setLoading(btn, loading, label) {
  btn.disabled = loading;
  btn.textContent = loading ? 'Verifying...' : label;
}

async function handleLogin(url, payload, btn, label) {
  setLoading(btn, true, label);

  try {
    const res = await fetch(url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payload)
    });

    let data = {};
    try {
      data = await res.json();
    } catch (err) {
      data = {};
    }

    if (res.ok && data.success) {
      window.location.href = '/dodo';
      return;
    }

    showAlert(data.error || 'Login failed');
  } catch (err) {
    showAlert('Connection error. Please try again.');
  } finally {
    setLoading(btn, false, label);
  }
}

const secretForm = document.getElementById('secretForm');
const firebaseForm = document.getElementById('firebaseForm');
const secretBtn = document.getElementById('secretBtn');
const firebaseBtn = firebaseForm.querySelector('button');

secretForm.addEventListener('submit', function (event) {
  event.preventDefault();
  const secret = document.getElementById('secretKey').value;
  handleLogin('/dodo/api/login-secret', { secret }, secretBtn, 'Sign In with Secret');
});

firebaseForm.addEventListener('submit', function (event) {
  event.preventDefault();
  const token = document.getElementById('firebaseToken').value.trim();
  if (!token) {
    showAlert('Please enter a Firebase token');
    return;
  }
  handleLogin('/dodo/api/login-firebase', { token }, firebaseBtn, 'Verify Firebase Token');
});
