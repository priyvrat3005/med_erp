import { NavLink, Route, Routes } from 'react-router-dom';

// Placeholder screens. Each is built in its own task (see ../tasks.md).
const Page = ({ title, task }: { title: string; task: string }) => (
  <div style={{ padding: 24 }}>
    <h1>{title}</h1>
    <p>Not implemented yet. See task {task}.</p>
  </div>
);

const nav = [
  ['/', 'Billing', 'T3.3'],
  ['/inventory', 'Inventory', 'T1.3'],
  ['/purchases', 'Purchases', 'T2.2'],
  ['/reports', 'Reports', 'T2.3'],
  ['/gst', 'GST', 'T6.1'],
  ['/customers', 'Customers', 'T1.4'],
  ['/settings', 'Settings', 'T5.2'],
] as const;

export default function App() {
  return (
    <div style={{ display: 'flex', height: '100vh', fontFamily: 'system-ui, sans-serif' }}>
      <nav style={{ width: 180, borderRight: '1px solid #ddd', padding: 12 }}>
        {nav.map(([to, label]) => (
          <div key={to} style={{ margin: '8px 0' }}>
            <NavLink to={to}>{label}</NavLink>
          </div>
        ))}
      </nav>
      <main style={{ flex: 1, overflow: 'auto' }}>
        <Routes>
          {nav.map(([to, label, task]) => (
            <Route key={to} path={to} element={<Page title={label} task={task} />} />
          ))}
        </Routes>
      </main>
    </div>
  );
}
