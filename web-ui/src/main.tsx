import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import 'bootstrap-icons/font/bootstrap-icons.css';
import '../../App.Native.UGreenLED/app/www/css/style.css';
import './theme.css';
import './ios18.css';
import './motion.css';
import { App } from './ui/App';

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <App />
  </StrictMode>,
);
