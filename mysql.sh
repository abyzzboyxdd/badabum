cat <<EOF | sudo tee /etc/yum.repos.d/mariadb.repo
[mariadb]
name = MariaDB
baseurl = https://rpm.mariadb.org/10.5/centos7-amd64
gpgkey=https://rpm.mariadb.org/RPM-GPG-KEY-MariaDB
gpgcheck=1
EOF
