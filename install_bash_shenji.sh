#!/bin/bash

#### Install bash-4.1-shenji.tar.gz ####
echo "Begin To Install bash-4.1"
sudo tar -xf bash-4.1-shenji.tar.gz && cd bash-4.1
sudo yum install -y make gcc gcc-c++ redhat-lsb-core
if sudo ./configure --prefix=/usr/local/bash_4.1 && sudo make && sudo make install
    then
    echo "Install Sucessed"
else
    echo "Install Failed,Check make or make install"
    exit 3
fi
sudo echo "/usr/local/bash_4.1/bin/bash" >> /etc/shells
sudo mv /bin/bash /bin/bash.bak
sudo ln -s /usr/local/bash_4.1/bin/bash /bin/bash
#sudo sed -i '/root/s#/bin/bash#/usr/local/bash_4.1/bin/bash#' /etc/passwd
#sudo sed -i '/ycf/s#/bin/bash#/usr/local/bash_4.1/bin/bash#' /etc/passwd

#### config server ####
echo "Begin To config Server"
chmod 666 /var/log/secure
test -f /var/log/keys || touch /var/log/keys
chmod 666 /var/log/keys
test -f /var/log/ssh_key_fing || touch /var/log/ssh_key_fing
chmod 666 /var/log/ssh_key_fing
cat > /etc/CheckUser.sh << EOF
#!/bin/bash
#conding:utf-8
pid=\$PPID
test -f /var/log/keys || touch /var/log/keys

test -f /var/log/ssh_key_fing || touch /var/log/ssh_key_fing

#在自己home目录得到所有的key，如果/var/log/keys 没有的时候，添加进去
test -f \$HOME/.ssh/authorized_keys && while read line
do
    grep "\$line" /var/log/keys >/dev/null || echo "\$line" >> /var/log/keys
done < \$HOME/.ssh/authorized_keys
#得到每个key的指纹
cat /var/log/keys | while read LINE
do
    NAME=\$(echo \$LINE | awk '{print \$3}')
    echo \$LINE >/tmp/keys.log.\$pid
    KEY=\$(ssh-keygen -l -f /tmp/keys.log.\$pid | awk '{print \$2}')
    grep "\$KEY \$NAME" /var/log/ssh_key_fing >/dev/null || echo "\$KEY \$NAME" >> /var/log/ssh_key_fing
done
#如果是root用户，secure文件里面是通过PPID号验证指纹
if [ \$UID == 0 ]
then
    ppid=\$PPID
else
    #如果不是root用户，验证指纹的是另外一个进程号
    ppid=\`/bin/ps -ef | grep \$PPID |grep 'sshd:' |awk '{print \$3}'\`
fi
# 判断系统版本
system_version=\`lsb_release -a | awk '/Release/{print (\$NF < 7 ? "6":"7")}'\`
if [ x\$system_version = x7 ]
then
    #得到RSA_KEY和NAME_OF_KEY，用来bash4.1得到历史记录
    RSA_KEY=\`/bin/egrep 'Accepted publickey' /var/log/secure | /bin/egrep "\$ppid" | /bin/awk '{print \$NF}' | tail -1\`
    #得到PAM_RHOST_PORT
    PAM_RHOST_PORT=\`/bin/egrep 'Accepted publickey' /var/log/secure | /bin/awk 'BEGIN{OFS=":";} {print \$(NF-5),\$(NF-3)}' | tail -1\`
else
    #得到RSA_KEY和NAME_OF_KEY，用来bash4.1得到历史记录
    RSA_KEY=\`/bin/egrep 'Found matching RSA key' /var/log/secure | /bin/egrep "\$ppid" | /bin/awk '{print \$NF}' | tail -1\`
    #得到PAM_RHOST_PORT
    PAM_RHOST_PORT=\`/bin/egrep 'Accepted' /var/log/secure | /bin/awk 'BEGIN{OFS=":";} {print \$(NF-3),\$(NF-1)}' | tail -1\`
fi
if [ -n "\$RSA_KEY" ];then
    NAME_OF_KEY=\`/bin/egrep "\$RSA_KEY" /var/log/ssh_key_fing | /bin/awk '{print \$NF}'\`
fi
#把NAME_OF_KEY设置为只读
readonly NAME_OF_KEY PAM_RHOST_PORT
export NAME_OF_KEY PAM_RHOST_PORT
/bin/rm /tmp/keys.log.\$pid
EOF
chmod 666 /etc/CheckUser.sh
sudo echo "test -f /etc/CheckUser.sh && . /etc/CheckUser.sh" >> /etc/profile
# 清屏有可能会在7版本系统上失效，添加清屏快捷键
sudo echo "bind -x '\"\C-l\": clear'" >> /etc/profile
sudo echo "test -z \"\$BASH_EXECUTION_STRING\" || { test -f /etc/CheckUser.sh && . /etc/CheckUser.sh; logger -t -bash -s \"HISTORY: RHOST_PORT=\$PAM_RHOST_PORT PID=00 PPID=\$PPID SID=00  User=remote_user USER=\$NAME_OF_KEY CMD=\$BASH_EXECUTION_STRING \" >/dev/null 2>&1;}" >> /etc/bashrc
echo "Config successed"
#### config sshd_config ####
echo "Beging Config sshd_config"
sudo sed -i 's/#LogLevel INFO/LogLevel DEBUG/g' /etc/ssh/sshd_config
if sudo /etc/init.d/sshd restart
    then
    echo "SSH restart successed"
fi
#### config logrotate ####
cat > /etc/logrotate.d/bash_audit  << EOF
/var/log/bash_audit.log
{
        monthly
        rotate 12
        copytruncate
        compress
        delaycompress
        missingok
        notifempty
}
EOF
#### config rsyslog.conf ####
echo "rsyslog.conf edit"
sudo sed -i '/GLOBAL DIRECTIVES/a \$template ycfformat,"%$NOW% %TIMESTAMP:8:15% %hostname% %syslogtag% %msg%\\n"' /etc/rsyslog.conf
sudo sed -i 's/RSYSLOG_TraditionalFileFormat/ycfformat/g' /etc/rsyslog.conf
sudo echo "user.debug                                             /var/log/bash_audit.log" >> /etc/rsyslog.conf
if sudo service rsyslog restart
	then
	echo "rsyslog restart successed,All config done"
fi
