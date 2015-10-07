# Class: passenger_nginx
#
# This module installs Nginx and its default configuration using rvm as the provider.
#
# Parameters:
#   $user
#       Into whose /home directory rvm will install
#   $ruby_version
#       Ruby version to install.
#   $logdir
#      Nginx's log directory.
#   $installdir
#      Nginx's install directory.
#   $www
#      Base directory for
#
# Sample Usage:  include passenger_nginx
class passenger_nginx (
  $user,
  $ruby_version,
  $gemset = "",
  $passenger_version = '4.0.19',
  $logdir = '/var/log/nginx',
  $installdir = '/opt/nginx',
  $www = '/var/www' ) {

    $options = "--auto --auto-download  --prefix=${installdir}"
    $passenger_deps = [ 'libcurl4-openssl-dev' ]
    $rvm_path = "/home/${user}/.rvm"
    $rvm_bin = "/home/${user}/.rvm/bin"
    $rvm_gems_dir = "/home/${user}/.rvm/gems/${ruby_version}/gems"

    $passenger_install_paths = [
      "/home/${user}/.rvm/bin",
      "/home/${user}/.rvm/gems/${ruby_version}/bin",
      "/home/${user}/.rvm/gems/${ruby_version}/gems/passenger-${passenger_version}/bin/",
      "/home/${user}/.rvm/rubies/${ruby_version}/bin",
      "/usr/local/bin",
      "/usr/bin",
      "/bin",
    ]

    exec { 'passenger-install':
      path      => $passenger_install_paths,
      #path      => "${rvm_bin}:${rvm_path}/gems/${ruby_version}/bin:${rvm_gems_dir}/passenger-${passenger_version}/bin:${rvm_path}/rubies/${ruby_version}/bin:/usr/local/bin:/usr/bin:/bin"
      command   => "/bin/su - ${user} -c 'gem install -V passenger --version ${passenger_version}'",
      #user      => $user,
      creates   => "${rvm_gems_dir}/passenger-${passenger_version}",
      timeout   => 0,
      logoutput => 'on_failure', #true,
      require   => [Rvm::Rvmuser[$user],],
    }

    exec { 'create container':
      command => "/bin/mkdir ${www} && /bin/chown ${user}:$user ${www}",
      unless  => "/usr/bin/test -d ${www}",
      before  => Exec['passenger-install-nginx-module']
    }

    $nginx_dirs = [
      $installdir,
      "${installdir}/conf"
    ]

    file { $nginx_dirs:
      owner  => "${user}",
      group  => "${user}",
      mode   => '0644',
      ensure => directory,
      before => Exec['passenger-install-nginx-module']
    }

    exec { 'passenger-install-nginx-module':
      command     => "/bin/su - ${user} -c '${rvm_gems_dir}/passenger-${passenger_version}/bin/passenger-install-nginx-module ${options}'",
      environment => ["HOME=/home/${user}"],
      path        => "${rvm_bin}:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin",
      creates     => "${installdir}/sbin/nginx",
      require     => [ Package[$passenger_deps], Exec['passenger-install'], File[$nginx_dirs],],
    }

    file { 'nginx-config':
      path    => "${installdir}/conf/nginx.conf",
      owner  => "${user}",
      group  => "${user}",
      mode    => '0644',
      content => template('passenger_nginx/nginx.conf.erb'),
      require => Exec['passenger-install-nginx-module'],
    }

    exec { 'create-sites-conf':
      path    => ['/usr/bin','/bin'],
      user    => "${user}",
      unless  => "/usr/bin/test -d  ${installdir}/conf/sites-available && /usr/bin/test -d ${installdir}/conf/sites-enabled",
      command => "/bin/mkdir  ${installdir}/conf/sites-available && /bin/mkdir ${installdir}/conf/sites-enabled",
      require => Exec['passenger-install-nginx-module'],
    }

    file { 'nginx-service':
      path      => '/etc/init.d/nginx',
      owner  => "${user}",
      group  => "${user}",
      mode      => '0755',
      content   => template('passenger_nginx/nginx.init.erb'),
      require   => File['nginx-config'],
      subscribe => File['nginx-config'],
    }

    file { $logdir:
      ensure => directory,
      owner  => "${user}",
      group  => "${user}",
      mode   => '0644'
    }

    service { 'nginx':
      ensure     => running,
      enable     => true,
      hasrestart => true,
      hasstatus  => true,
      subscribe  => File['nginx-config'],
      require    => [ File[$logdir], File['nginx-service']],
    }

}
