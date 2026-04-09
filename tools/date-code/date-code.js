(function () {
  // 1-based month arrays: index 0 unused for simpler mapping.
  const base2023 = [
    0, 1143425, 1103300, 1090155, 1083806, 1080146, 1077850, 1076313, 1075272,
    1074552, 1074044, 1073713, 1073492,
  ];

  const annualStep = [
    0, 5154, 4965, 4908, 4879, 4861, 4849, 4840, 4834, 4829, 4825, 4822, 4819,
  ];

  // Calibrated drift adjustments for years after 2023:
  // adjustment = y * linear + y^2 * quadratic where y = (year - 2023)
  // The terms are fitted from known 2024-2026 month-end values.
  const yearDriftLinear = [
    0, -3.236842105263158, 2.763157894736842, 10.473684210526315,
    8.368421052631579, 14, 14, 14, -0.5, -0.5, 12.5, 12.5, 12.5,
  ];

  const yearDriftQuadratic = [
    0, 0.34210526315789475, 0.34210526315789475, -3.6842105263157894,
    -3.4210526315789473, -7, -7, -7, 0, 0, -6.5, -6.5, -6.5,
  ];

  // Raw training data used to calibrate the model (kept as permanent background).
  const SEED_DATA = {
    "2023-01-31": 1143425,
    "2023-02-28": 1103300,
    "2023-03-31": 1090155,
    "2023-04-30": 1083806,
    "2023-05-31": 1080146,
    "2023-06-30": 1077850,
    "2023-07-31": 1076313,
    "2023-08-31": 1075272,
    "2023-09-30": 1074552,
    "2023-10-31": 1074044,
    "2023-11-30": 1073713,
    "2023-12-31": 1073492,
    "2024-01-31": 1148572,
    "2024-02-29": 1108264,
    "2024-03-31": 1095072,
    "2024-04-30": 1088692,
    "2024-05-31": 1085014,
    "2024-06-30": 1082706,
    "2024-07-31": 1081160,
    "2024-10-31": 1078875,
    "2024-11-30": 1078541,
    "2024-12-31": 1078317,
    "2025-01-31": 1153732,
    "2025-02-28": 1113241,
    "2025-03-31": 1099975,
    "2025-04-30": 1093565,
    "2025-05-31": 1089868,
    "2025-06-30": 1087548,
    "2025-07-31": 1085993,
    "2025-08-31": 1084939,
    "2025-09-30": 1084209,
    "2025-10-31": 1083693,
    "2025-11-30": 1083356,
    "2025-12-31": 1083129,
    "2026-01-31": 1158879,
    "2026-02-28": 1118205,
    "2026-03-31": 1104878,
    "2026-04-30": 1098438,
  };

  const USER_DATA_KEY = "dcpUserData";

  function loadUserData() {
    try {
      return JSON.parse(localStorage.getItem(USER_DATA_KEY) || "{}");
    } catch (_) {
      return {};
    }
  }

  function saveUserData(obj) {
    localStorage.setItem(USER_DATA_KEY, JSON.stringify(obj));
  }

  function getAllKnown() {
    return { ...SEED_DATA, ...loadUserData() };
  }

  function endOfMonthDay(year, month1to12) {
    return new Date(year, month1to12, 0).getDate();
  }

  function codeForDate(date) {
    const year = date.getFullYear();
    const month = date.getMonth() + 1;
    const day = date.getDate();

    const yearOffset = year - 2023;
    const eom = endOfMonthDay(year, month);

    // Base month profile + month-specific yearly drift.
    let value = base2023[month] + yearOffset * annualStep[month];

    // Calibrated correction for post-2023 drift.
    value +=
      yearOffset * yearDriftLinear[month] +
      yearOffset * yearOffset * yearDriftQuadratic[month];

    // Small day adjustment away from end-of-month.
    value += (day - eom) * 8;

    return Math.round(value);
  }

  function formatNumber(n) {
    return n.toLocaleString("en-US");
  }

  function setToday(inputEl) {
    const today = new Date();
    const yyyy = today.getFullYear();
    const mm = String(today.getMonth() + 1).padStart(2, "0");
    const dd = String(today.getDate()).padStart(2, "0");
    inputEl.value = `${yyyy}-${mm}-${dd}`;
  }

  function toIsoDate(year, month1to12, day) {
    const mm = String(month1to12).padStart(2, "0");
    const dd = String(day).padStart(2, "0");
    return `${year}-${mm}-${dd}`;
  }

  function parseInputDate(inputEl) {
    if (!inputEl.value) {
      return null;
    }

    const date = new Date(`${inputEl.value}T00:00:00`);
    if (Number.isNaN(date.getTime())) {
      return null;
    }

    return date;
  }

  function renderForecast(startDate, outputBodyEl, count) {
    const known = getAllKnown();
    let year = startDate.getFullYear();
    let month = startDate.getMonth() + 1;
    let rowsHtml = "";

    for (let i = 0; i < count; i += 1) {
      const eom = endOfMonthDay(year, month);
      const monthEndDate = new Date(year, month - 1, eom);
      const code = codeForDate(monthEndDate);
      const isoDate = toIsoDate(year, month, eom);

      const actual = known[isoDate];
      const actualCell = actual !== undefined ? formatNumber(actual) : "-";
      let diffCell = "-";
      let diffClass = "";
      if (actual !== undefined) {
        const diff = actual - code;
        diffClass = diff >= 0 ? "diff-pos" : "diff-neg";
        diffCell = (diff >= 0 ? "+" : "") + diff.toLocaleString("en-US");
      }

      rowsHtml += `<tr>
        <td>${isoDate}</td>
        <td>${formatNumber(code)}</td>
        <td>${actualCell}</td>
        <td class="${diffClass}">${diffCell}</td>
      </tr>`;

      month += 1;
      if (month > 12) {
        month = 1;
        year += 1;
      }
    }

    outputBodyEl.innerHTML = rowsHtml;
  }

  function renderActuals(outputBodyEl) {
    const userData = loadUserData();
    const allEntries = Object.entries(SEED_DATA)
      .map(([d, v]) => ({ date: d, code: v, source: "seed" }))
      .concat(
        Object.entries(userData).map(([d, v]) => ({
          date: d,
          code: v,
          source: "user",
        })),
      );
    allEntries.sort((a, b) => b.date.localeCompare(a.date));

    let html = "";
    for (const { date, code, source } of allEntries) {
      const tagClass = source === "seed" ? "tag-seed" : "tag-user";
      const rowClass = source === "seed" ? ' class="seed-row"' : "";
      const delBtn =
        source === "user"
          ? `<button class="del-btn" data-date="${date}" title="Remove">✕</button>`
          : "";
      html += `<tr${rowClass}>
        <td>${date}</td>
        <td>${formatNumber(code)}</td>
        <td><span class="tag ${tagClass}">${source}</span></td>
        <td>${delBtn}</td>
      </tr>`;
    }

    outputBodyEl.innerHTML =
      html || '<tr><td colspan="4">No data yet.</td></tr>';

    outputBodyEl.querySelectorAll(".del-btn").forEach((btn) => {
      btn.addEventListener("click", () => {
        deleteDataPoint(btn.dataset.date, outputBodyEl);
      });
    });
  }

  function addDataPoint(isoDate, code, actualsBodyEl) {
    const userData = loadUserData();
    userData[isoDate] = Number(code);
    saveUserData(userData);
    renderActuals(actualsBodyEl);
    generateForecast();
  }

  function deleteDataPoint(isoDate, actualsBodyEl) {
    const userData = loadUserData();
    delete userData[isoDate];
    saveUserData(userData);
    renderActuals(actualsBodyEl);
    generateForecast();
  }

  function copyForAI() {
    const known = getAllKnown();
    const rows = Object.entries(known)
      .sort(([a], [b]) => a.localeCompare(b))
      .map(([date, code]) => ({
        date,
        actual: code,
        predicted: codeForDate(new Date(`${date}T00:00:00`)),
        source: SEED_DATA[date] !== undefined ? "seed" : "user",
      }));
    const json = JSON.stringify(rows, null, 2);
    navigator.clipboard.writeText(json).then(() => {
      const btn = document.getElementById("copyAiBtn");
      const orig = btn.textContent;
      btn.textContent = "Copied!";
      setTimeout(() => {
        btn.textContent = orig;
      }, 1500);
    });
  }

  function calculate() {
    const inputEl = document.getElementById("dateInput");
    const outputEl = document.getElementById("codeOutput");
    const formulaEl = document.getElementById("formulaOutput");

    const date = parseInputDate(inputEl);

    if (!date) {
      outputEl.textContent = "Please pick a date";
      formulaEl.textContent = "Formula: -";
      return;
    }

    const year = date.getFullYear();
    const month = date.getMonth() + 1;
    const day = date.getDate();
    const yearOffset = year - 2023;
    const eom = endOfMonthDay(year, month);
    const baseValue = base2023[month];
    const annualPart = yearOffset * annualStep[month];
    const linearDriftPart = yearOffset * yearDriftLinear[month];
    const quadraticDriftPart =
      yearOffset * yearOffset * yearDriftQuadratic[month];
    const dayPart = (day - eom) * 8;

    outputEl.textContent = formatNumber(codeForDate(date));
    formulaEl.textContent =
      `Formula: base ${baseValue} + year drift ${Math.round(annualPart + linearDriftPart + quadraticDriftPart)} ` +
      `+ day adjust ${dayPart}`;
  }

  function generateForecast() {
    const inputEl = document.getElementById("dateInput");
    const outputBodyEl = document.getElementById("forecastOutput");
    const startDate = parseInputDate(inputEl) || new Date();
    renderForecast(startDate, outputBodyEl, 12);
  }

  const inputEl = document.getElementById("dateInput");
  const buttonEl = document.getElementById("calcBtn");
  const forecastButtonEl = document.getElementById("forecastBtn");
  const addDataFormEl = document.getElementById("addDataForm");
  const actualsBodyEl = document.getElementById("actualsOutput");
  const copyAiBtnEl = document.getElementById("copyAiBtn");

  setToday(inputEl);
  calculate();
  generateForecast();
  renderActuals(actualsBodyEl);

  buttonEl.addEventListener("click", calculate);
  inputEl.addEventListener("change", calculate);
  forecastButtonEl.addEventListener("click", generateForecast);

  addDataFormEl.addEventListener("submit", (e) => {
    e.preventDefault();
    const dateVal = document.getElementById("addDateInput").value;
    const codeVal = document.getElementById("addCodeInput").value;
    if (dateVal && codeVal) {
      addDataPoint(dateVal, codeVal, actualsBodyEl);
      addDataFormEl.reset();
    }
  });

  copyAiBtnEl.addEventListener("click", copyForAI);
})();
