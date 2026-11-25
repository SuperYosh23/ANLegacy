import { createContext, useContext, useState } from 'react';

const NavigationContext = createContext();

export const useNavigate = () => {
  const ctx = useContext(NavigationContext);
  if (!ctx) throw new Error('useNavigate must be used within NavigationProvider');
  return ctx;
};

export const NavigationProvider = ({ children }) => {
  const [subPage, setSubPage] = useState(null);

  const navigate = (page) => {
    setSubPage(page);
  };

  const navigateBack = () => {
    setSubPage(null);
  };

  return (
    <NavigationContext.Provider value={{ subPage, navigate, navigateBack }}>
      {children}
    </NavigationContext.Provider>
  );
};
