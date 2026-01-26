// Network Checker - Main JavaScript

const Checker = {
  refreshInterval: null,
  countdownInterval: null,
  charts: {},
  hostData: [],

  init() {
    // Only run dashboard logic on the dashboard page
    // Check for dashboard-specific element to avoid conflicts with host detail page
    const hostStatusGrid = document.getElementById('host-status-grid');
    if (!hostStatusGrid) return;

    this.bindEvents();
    this.loadDashboard();
    this.loadSchedulerStatus();
    this.startAutoRefresh();
    this.startCountdownUpdates();
  },

  bindEvents() {
    const timeRangeSelect = document.getElementById('time-range');
    if (timeRangeSelect) {
      timeRangeSelect.addEventListener('change', (e) => {
        const customRangePicker = document.getElementById('custom-range');
        if (e.target.value === 'custom') {
          if (customRangePicker) {
            customRangePicker.style.display = 'flex';
            // Set default values to last 24 hours
            const now = new Date();
            const yesterday = new Date(now - 24 * 60 * 60 * 1000);
            document.getElementById('range-end').value = now.toISOString().slice(0, 16);
            document.getElementById('range-start').value = yesterday.toISOString().slice(0, 16);
          }
        } else {
          if (customRangePicker) customRangePicker.style.display = 'none';
          this.loadCharts();
        }
      });
    }

    const autoRefreshToggle = document.getElementById('auto-refresh');
    if (autoRefreshToggle) {
      autoRefreshToggle.addEventListener('change', (e) => {
        if (e.target.checked) {
          this.startAutoRefresh();
        } else {
          this.stopAutoRefresh();
        }
      });
    }
  },

  applyCustomRange() {
    const start = document.getElementById('range-start').value;
    const end = document.getElementById('range-end').value;

    if (!start || !end) {
      alert('Please select both start and end dates');
      return;
    }

    this.customRange = { start, end };
    this.loadCharts();
  },

  getTimeRangeParams() {
    const timeRange = document.getElementById('time-range')?.value || '24h';

    if (timeRange === 'custom' && this.customRange) {
      return `start=${encodeURIComponent(this.customRange.start)}&end=${encodeURIComponent(this.customRange.end)}`;
    }

    return `range=${timeRange}`;
  },

  startAutoRefresh() {
    this.stopAutoRefresh();
    this.refreshInterval = setInterval(() => {
      this.loadHostStatus();
      this.loadSchedulerStatus();
    }, 30000); // Refresh every 30 seconds
  },

  stopAutoRefresh() {
    if (this.refreshInterval) {
      clearInterval(this.refreshInterval);
      this.refreshInterval = null;
    }
  },

  startCountdownUpdates() {
    // Update countdowns every second
    this.countdownInterval = setInterval(() => {
      this.updateCountdowns();
    }, 1000);
  },

  updateCountdowns() {
    this.hostData.forEach(host => {
      const el = document.getElementById(`countdown-${host.id}`);
      if (el && host.next_test_at) {
        el.textContent = this.formatCountdown(host.next_test_at);
      }
    });
  },

  formatCountdown(isoString) {
    const nextTest = new Date(isoString);
    const now = new Date();
    const diffMs = nextTest - now;

    if (diffMs <= 0) return 'Testing...';

    const diffSecs = Math.floor(diffMs / 1000);
    const mins = Math.floor(diffSecs / 60);
    const secs = diffSecs % 60;

    if (mins > 0) {
      return `${mins}m ${secs}s`;
    }
    return `${secs}s`;
  },

  async loadDashboard() {
    await this.loadHostStatus();
    await this.loadCharts();
  },

  async loadSchedulerStatus() {
    const statusEl = document.getElementById('scheduler-status');
    if (!statusEl) return;

    try {
      const response = await fetch('/api/scheduler/status');
      const data = await response.json();

      if (data.running) {
        statusEl.innerHTML = `<span class="status-badge up">Scheduler Running</span> (every ${data.test_interval}s)`;
      } else {
        statusEl.innerHTML = '<span class="status-badge down">Scheduler Stopped</span>';
      }
    } catch (error) {
      console.error('Failed to load scheduler status:', error);
    }
  },

  async runTestsNow() {
    const btn = document.getElementById('run-tests-btn');
    if (!btn) return;

    btn.disabled = true;
    btn.textContent = 'Running...';

    try {
      const response = await fetch('/api/tests/run', { method: 'POST' });
      const data = await response.json();

      // Refresh the dashboard
      await this.loadHostStatus();
      await this.loadCharts();

      btn.textContent = 'Tests Complete!';
      setTimeout(() => {
        btn.textContent = 'Run Tests Now';
        btn.disabled = false;
      }, 2000);
    } catch (error) {
      console.error('Failed to run tests:', error);
      btn.textContent = 'Error!';
      setTimeout(() => {
        btn.textContent = 'Run Tests Now';
        btn.disabled = false;
      }, 2000);
    }
  },

  async loadHostStatus() {
    const grid = document.getElementById('host-status-grid');
    if (!grid) return;

    try {
      const response = await fetch('/api/hosts/status');
      const data = await response.json();

      if (data.hosts && data.hosts.length > 0) {
        this.hostData = data.hosts;
        grid.innerHTML = data.hosts.map(host => this.renderHostCard(host)).join('');
      } else {
        this.hostData = [];
        grid.innerHTML = '<p class="loading">No hosts configured. <a href="/hosts">Add a host</a> to get started.</p>';
      }
    } catch (error) {
      console.error('Failed to load host status:', error);
      grid.innerHTML = '<p class="loading">Failed to load host status.</p>';
    }
  },

  renderHostCard(host) {
    const statusClass = host.reachable ? 'status-up' : 'status-down';
    const latency = host.latency_ms ? `${host.latency_ms.toFixed(1)} ms` : 'N/A';
    const jitter = host.jitter_ms ? `${host.jitter_ms.toFixed(1)} ms` : 'N/A';
    const lastTested = host.last_tested ? this.formatRelativeTime(host.last_tested) : 'Never';
    const testType = (host.test_type || 'ping').toUpperCase();
    const countdown = host.next_test_at ? this.formatCountdown(host.next_test_at) : '--';

    return `
      <a href="/hosts/${host.id}" class="host-card ${statusClass}">
        <div class="host-card-header">
          <div class="host-name">${this.escapeHtml(host.name)}</div>
          <span class="test-type-badge">${testType}</span>
        </div>
        <div class="host-address">${this.escapeHtml(host.address)}${host.port ? ':' + host.port : ''}</div>
        <div class="host-metrics">
          <div class="metric">
            <span class="metric-label">Latency</span>
            <span class="metric-value">${latency}</span>
          </div>
          <div class="metric">
            <span class="metric-label">Jitter</span>
            <span class="metric-value">${jitter}</span>
          </div>
          <div class="metric">
            <span class="metric-label">Status</span>
            <span class="status-badge ${host.reachable ? 'up' : 'down'}">${host.reachable ? 'UP' : 'DOWN'}</span>
          </div>
        </div>
        <div class="host-footer">
          <span class="last-tested">Last: ${lastTested}</span>
          <span class="next-test">Next: <span id="countdown-${host.id}">${countdown}</span></span>
        </div>
      </a>
    `;
  },

  formatRelativeTime(isoString) {
    const date = new Date(isoString);
    const now = new Date();
    const diffMs = now - date;
    const diffSecs = Math.floor(diffMs / 1000);
    const diffMins = Math.floor(diffSecs / 60);
    const diffHours = Math.floor(diffMins / 60);
    const diffDays = Math.floor(diffHours / 24);

    if (diffSecs < 60) return 'just now';
    if (diffMins < 60) return `${diffMins}m ago`;
    if (diffHours < 24) return `${diffHours}h ago`;
    if (diffDays < 7) return `${diffDays}d ago`;
    return date.toLocaleDateString();
  },

  async loadCharts() {
    const rangeParams = this.getTimeRangeParams();
    await Promise.all([
      this.loadLatencyChartsByType(rangeParams),
      this.loadJitterChart(rangeParams),
      this.loadReachabilityChart(rangeParams)
    ]);
  },

  // Detect if current theme is light or dark
  getChartThemeMode() {
    const theme = document.body.getAttribute('data-theme') || 'dark-default';
    return theme.startsWith('light-') ? 'light' : 'dark';
  },

  // Extended color palette for up to 20 hosts
  chartColors: [
    '#00bf63', '#e94560', '#ffc107', '#0f3460', '#9c27b0',
    '#00bcd4', '#ff5722', '#8bc34a', '#3f51b5', '#ff9800',
    '#607d8b', '#e91e63', '#4caf50', '#2196f3', '#ffeb3b',
    '#795548', '#009688', '#673ab7', '#cddc39', '#f44336'
  ],

  // Test type display names and order
  testTypeLabels: {
    'ping': 'Ping',
    'tcp': 'TCP',
    'udp': 'UDP',
    'http': 'HTTP',
    'dns': 'DNS'
  },

  async loadLatencyChartsByType(rangeParams) {
    const container = document.getElementById('latency-charts-container');
    if (!container) return;

    try {
      const response = await fetch(`/api/measurements/latency/by-type?${rangeParams}`);
      const data = await response.json();

      const testTypes = data.test_types || [];
      const seriesByType = data.series_by_type || {};

      // Destroy existing latency charts
      Object.keys(this.charts).forEach(key => {
        if (key.startsWith('latency-')) {
          this.charts[key].destroy();
          delete this.charts[key];
        }
      });

      if (testTypes.length === 0) {
        container.innerHTML = '<p class="loading">No latency data available</p>';
        return;
      }

      // Build chart containers HTML
      const chartsHtml = testTypes.map(type => {
        const label = this.testTypeLabels[type] || type.toUpperCase();
        return `
          <div class="chart-container">
            <h3>Latency - ${label}</h3>
            <div id="latency-chart-${type}" class="chart"></div>
          </div>
        `;
      }).join('');

      container.innerHTML = `<div class="charts-grid">${chartsHtml}</div>`;

      // Render each chart
      for (const type of testTypes) {
        const series = seriesByType[type] || [];
        await this.renderLatencyChart(type, series);
      }
    } catch (error) {
      console.error('Failed to load latency charts:', error);
      container.innerHTML = '<p class="loading">Failed to load latency charts</p>';
    }
  },

  async renderLatencyChart(testType, series) {
    const container = document.getElementById(`latency-chart-${testType}`);
    if (!container) return;

    const seriesCount = series.length;

    const options = {
      chart: {
        type: 'line',
        height: seriesCount > 5 ? 300 : 250,
        background: 'transparent',
        toolbar: {
          show: true,
          offsetY: 0,
          tools: {
            download: true,
            selection: true,
            zoom: true,
            zoomin: true,
            zoomout: true,
            pan: true,
            reset: true
          }
        },
        animations: {
          enabled: true,
          easing: 'easeinout',
          speed: 300
        }
      },
      theme: {
        mode: this.getChartThemeMode()
      },
      colors: this.chartColors,
      series: series,
      xaxis: {
        type: 'datetime',
        labels: {
          datetimeUTC: false
        }
      },
      yaxis: {
        title: {
          text: 'Latency (ms)'
        },
        min: 0
      },
      stroke: {
        curve: 'smooth',
        width: 2
      },
      tooltip: {
        x: {
          format: 'MMM dd, HH:mm'
        }
      },
      legend: {
        show: true,
        showForSingleSeries: true,
        position: 'bottom',
        horizontalAlign: 'center',
        floating: false,
        fontSize: seriesCount > 5 ? '11px' : '12px',
        offsetY: 5,
        itemMargin: {
          horizontal: 8,
          vertical: 3
        }
      },
      noData: {
        text: 'No data available',
        style: {
          color: '#a0a0a0'
        }
      }
    };

    const chartKey = `latency-${testType}`;
    this.charts[chartKey] = new ApexCharts(container, options);
    this.charts[chartKey].render();
  },

  async loadJitterChart(rangeParams) {
    const container = document.getElementById('jitter-chart');
    if (!container) return;

    try {
      const response = await fetch(`/api/measurements/jitter?${rangeParams}`);
      const data = await response.json();
      const seriesCount = (data.series || []).length;

      const options = {
        chart: {
          type: 'line',
          height: seriesCount > 10 ? 350 : 300,
          background: 'transparent',
          toolbar: {
            show: true,
            offsetY: 0,
            tools: {
              download: true,
              selection: true,
              zoom: true,
              zoomin: true,
              zoomout: true,
              pan: true,
              reset: true
            }
          }
        },
        theme: {
          mode: this.getChartThemeMode()
        },
        colors: this.chartColors,
        series: data.series || [],
        xaxis: {
          type: 'datetime',
          labels: {
            datetimeUTC: false
          }
        },
        yaxis: {
          title: {
            text: 'Jitter (ms)'
          },
          min: 0
        },
        stroke: {
          curve: 'smooth',
          width: 2
        },
        tooltip: {
          x: {
            format: 'MMM dd, HH:mm'
          }
        },
        legend: {
          show: true,
          showForSingleSeries: true,
          position: 'bottom',
          horizontalAlign: 'center',
          floating: false,
          fontSize: seriesCount > 10 ? '11px' : '12px',
          offsetY: 5,
          itemMargin: {
            horizontal: 8,
            vertical: 3
          }
        },
        noData: {
          text: 'No data available',
          style: {
            color: '#a0a0a0'
          }
        }
      };

      container.innerHTML = '';
      if (this.charts.jitter) {
        this.charts.jitter.destroy();
      }
      this.charts.jitter = new ApexCharts(container, options);
      this.charts.jitter.render();
    } catch (error) {
      console.error('Failed to load jitter chart:', error);
    }
  },

  async loadReachabilityChart(rangeParams) {
    const container = document.getElementById('reachability-chart');
    if (!container) return;

    try {
      const response = await fetch(`/api/measurements/reachability?${rangeParams}`);
      const data = await response.json();

      const options = {
        chart: {
          type: 'heatmap',
          height: 200,
          background: 'transparent',
          toolbar: {
            show: false
          }
        },
        theme: {
          mode: this.getChartThemeMode()
        },
        series: data.series || [],
        dataLabels: {
          enabled: false
        },
        colors: ['#00bf63'],
        plotOptions: {
          heatmap: {
            shadeIntensity: 0.5,
            colorScale: {
              ranges: [
                { from: 0, to: 50, color: '#dc3545', name: 'Down' },
                { from: 50, to: 90, color: '#ffc107', name: 'Degraded' },
                { from: 90, to: 100, color: '#00bf63', name: 'Up' }
              ]
            }
          }
        },
        xaxis: {
          type: 'datetime'
        },
        legend: {
          show: true,
          showForSingleSeries: true,
          position: 'bottom',
          horizontalAlign: 'center'
        },
        noData: {
          text: 'No data available',
          style: {
            color: '#a0a0a0'
          }
        }
      };

      container.innerHTML = '';
      if (this.charts.reachability) {
        this.charts.reachability.destroy();
      }
      this.charts.reachability = new ApexCharts(container, options);
      this.charts.reachability.render();
    } catch (error) {
      console.error('Failed to load reachability chart:', error);
    }
  },

  escapeHtml(text) {
    const div = document.createElement('div');
    div.textContent = text;
    return div.innerHTML;
  }
};

// Initialize when DOM is ready
document.addEventListener('DOMContentLoaded', () => Checker.init());
