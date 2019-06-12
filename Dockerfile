FROM alpine:3.9

ARG TAG
LABEL TAG=${TAG}

ENV JAVA_HOME /usr/lib/jvm/java-1.8-openjdk
ENV PATH ${PATH}:/usr/lib/jvm/java-1.8-openjdk/jre/bin:/usr/lib/jvm/java-1.8-openjdk/bin
ENV JENKINS_HOME /var/jenkins_home
ENV JENKINS_VERSION 2.164.3
ENV JENKINS_PLUGINS_LATEST true
ENV FC_LANG de-CH
ENV LC_CTYPE de_CH.UTF-8

# Add scripts and plugin list
COPY files /

# Packages
RUN set -ex;\
    apk update;\
    apk upgrade;\
    apk add --no-cache tini openjdk8 bash git curl fontconfig ttf-dejavu jq coreutils openssh docker nss;\
    rm -rf /var/cache/apk/*

# Install Jenkins and plugins from plugins.txt
RUN echo "*** Installing jenkins ***";\
    curl -sSL --create-dirs --retry 3 https://updates.jenkins.io/download/war/${JENKINS_VERSION}/jenkins.war -o /usr/share/jenkins/jenkins.war;\
    echo "*** Iterative solve and reduce plugin dependencies ***";\
    curl -sSO --retry 3 https://updates.jenkins.io/current/update-center.actual.json;\
    false; until [ $? -eq 0 ]; do \
       cp /var/jenkins_home/plugins.txt /var/jenkins_home/check;\
       jq --arg p "$(sed -e ':a;N;$!ba;s/\n/ /g' /var/jenkins_home/plugins.txt)" -r '.plugins[] | select([.name] | inside([$p]))| .dependencies[] | select(.optional == false)| .name + ":" + .version' update-center.actual.json >> /var/jenkins_home/plugins.txt;\
       sort -Vr /var/jenkins_home/plugins.txt | sort -u -t: -k1,1 -o /var/jenkins_home/plugins.txt;\
       cmp -s /var/jenkins_home/check /var/jenkins_home/plugins.txt;\
    done;\
    rm /var/jenkins_home/check;\
    echo "*** Jenkins install plugins from plugins.txt *** ";\
    while read plugin; do \
       if [ "${JENKINS_PLUGINS_LATEST}" == true ]; then plugin="${plugin%:*}:latest"; else plugin="${plugin%:*}:${plugin#*:}"; fi;\
       echo "*** Downloading ${plugin} ***";\
       curl -sSL --create-dirs --retry 3 https://updates.jenkins.io/download/plugins/${plugin%:*}/${plugin#*:}/${plugin%:*}.hpi -o /var/jenkins_home/plugins/${plugin%:*}.jpi;\
       touch /var/jenkins_home/plugins/${plugin%:*}.jpi.pinned;\
    done < /var/jenkins_home/plugins.txt

EXPOSE 8080 8443

ENTRYPOINT ["/sbin/tini", "--", "entrypoint.sh"]
CMD ["java", "${JAVA_OPTS}", "-XX:+UnlockExperimentalVMOptions", "-XX:+UseCGroupMemoryLimitForHeap", "-XX:MaxRAMFraction=2", "-XX:+HeapDumpOnOutOfMemoryError", "-XshowSettings:vm", "-Djava.awt.headless=true", "-Djenkins.install.runSetupWizard=false", "-jar", "/usr/share/jenkins/jenkins.war", "${JENKINS_OPTS}"]
