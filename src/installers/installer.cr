module Zap::Installers
  ALWAYS_INCLUDED = %w(package.json package-lock.json README LICENSE LICENCE)
  ALWAYS_IGNORED  = %w(.git CVS .svn .hg .lock-wscript .wafpickle-N .*.swp .DS_Store ._* npm-debug.log .npmrc node_modules config.gypi *.orig package-lock.json)

  abstract class Base
  end
end
