const authPaths = {
  '/login',
  '/register',
  '/auth-select',
  '/member/login',
  '/member/register',
};

const centerPaths = {
  '/onboarding',
  '/centers',
  '/centers/create',
  '/centers/join',
};

bool isMemberPath(String path) =>
    path == '/member/home' || path.startsWith('/member/');

bool isAdminPath(String path) => path == '/admin' || path.startsWith('/admin/');
