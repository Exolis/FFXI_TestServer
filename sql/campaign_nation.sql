-- MySQL dump 10.16  Distrib 10.2.8-MariaDB, for Win64 (AMD64)
--
-- Host: localhost    Database: dspdb
-- ------------------------------------------------------
-- Server version    10.2.8-MariaDB

--
-- Table structure for table `campaign_nation`
--

DROP TABLE IF EXISTS `campaign_nation`;
CREATE TABLE `campaign_nation` (
  `id` tinyint(2) unsigned NOT NULL,
  `reconnaissance` tinyint(2) unsigned NOT NULL DEFAULT 0,
  `morale` tinyint(3) unsigned NOT NULL DEFAULT 0,
  `prosperity` tinyint(2) unsigned NOT NULL DEFAULT 0,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `campaign_nation`
--

INSERT INTO `campaign_nation` VALUES (0,0,50,50); -- Sandoria
INSERT INTO `campaign_nation` VALUES (1,0,50,50); -- Bastok
INSERT INTO `campaign_nation` VALUES (2,0,50,50); -- Windurst
INSERT INTO `campaign_nation` VALUES (3,0,60,0); -- Orcish
INSERT INTO `campaign_nation` VALUES (4,0,60,0); -- Quadav
INSERT INTO `campaign_nation` VALUES (5,0,60,0); -- Yagudio
INSERT INTO `campaign_nation` VALUES (6,0,60,0); -- Kindred

-- Dump completed on 2018-06-09 17:04:32
