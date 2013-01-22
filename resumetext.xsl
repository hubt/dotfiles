<?xml version="1.0"?>
<xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
  <xsl:output method="text" />
  <xsl:template match="/resume">

  <xsl:call-template name="indent"/>
  <xsl:value-of select="//name" />
  <xsl:call-template name="lf"/>

  <xsl:call-template name="indent"/>
  <xsl:value-of select="//address1" />
  <xsl:call-template name="lf"/>

  <xsl:call-template name="indent"/>
  <xsl:value-of select="//address2" />
  <xsl:call-template name="lf"/>

  <xsl:call-template name="indent"/>
  <xsl:value-of select="//phone" />
  <xsl:call-template name="lf"/>

  <xsl:call-template name="indent"/>
  <xsl:value-of select="//url" />
  <xsl:call-template name="lf"/>
<xsl:text>
     _________________________________________________________________
Objective:

</xsl:text>
  <xsl:value-of select="//objective"/>
<xsl:text>
Skills:
</xsl:text>

  </xsl:template>
  <xsl:template name="indent"><xsl:text>  </xsl:text></xsl:template>
  <xsl:template name="lf"><xsl:text>
</xsl:text></xsl:template>
</xsl:stylesheet>
