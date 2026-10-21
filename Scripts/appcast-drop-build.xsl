<?xml version="1.0" encoding="UTF-8"?>
<!--
  Removes every <item> whose sparkle:version (element or enclosure attribute)
  equals the "build" parameter, and copies everything else unchanged.

  Why: generate_appcast matches items by version. If the feed already has an
  item for this build, it would update that item in place, keeping its channel
  tag and notes. Dropping the old item first makes generate_appcast write a
  fresh one. In normal use there is no such item: since #77 a stable tag goes
  on a different commit than its last beta, so it has its own CFBundleVersion,
  and release.yml refuses a tag whose commit another tag already deployed. The
  drop stays as a defensive step, for example for a re-run of the same tag. It
  was written for a stable tag on its beta's commit, the flow #77 superseded;
  see Design/sparkle-updates.md, 2.6.

  Usage: xsltproc with the string parameter "build" set to the build number,
  this stylesheet, and the current appcast.xml.

  XSLT 1.0 does not allow variables in match patterns, hence xsl:if inside
  the item template. cdata-section-elements keeps embedded notes in CDATA.
-->
<xsl:stylesheet version="1.0"
    xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
    xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <xsl:output method="xml" encoding="UTF-8" indent="yes" cdata-section-elements="description"/>
  <xsl:param name="build" select="''"/>

  <xsl:template match="@*|node()">
    <xsl:copy>
      <xsl:apply-templates select="@*|node()"/>
    </xsl:copy>
  </xsl:template>

  <xsl:template match="item">
    <xsl:if test="not(sparkle:version = $build) and not(enclosure/@sparkle:version = $build)">
      <xsl:copy>
        <xsl:apply-templates select="@*|node()"/>
      </xsl:copy>
    </xsl:if>
  </xsl:template>
</xsl:stylesheet>
