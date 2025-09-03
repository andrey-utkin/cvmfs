package pkg

import (
	"bufio"
	"fmt"
	"os"
	"os/exec"
	"regexp"
	"strconv"
	"sync"
	"time"

	"github.com/rs/zerolog"
	"github.com/rs/zerolog/log"
)

type GraftOptions struct {
	PriorityVal int64
	Debug       bool
	Priority    string
}

// Converts the priority value to the associated priority string, lease retry interval, and start offset
func PriorityToPriorityInfo(priority string) (string, int64) {
	priorityVal := LowPriorityVal
	switch priority {
	case HighPriority:
		priorityVal = HighPriorityVal
	case MedPriority:
		priorityVal = MedPriorityVal
	case LowPriority:
		fallthrough
	default:
		priorityVal = LowPriorityVal
	}
	return priority, int64(priorityVal*1.e6) - time.Now().Unix()
}

type GraftMetrics struct {
	Delta                         float64
	Files, Dirs, Links, Deletions int
	Priority                      string
	LeasePath                     string
	Revision                      string
}

// Perform a graft with the passed in db using the currently loaded cvmfs_swissknife module
func NewGraftOptions(priority string) GraftOptions {
	// initialize the option with sensitive default
	priorityString, priorityVal := PriorityToPriorityInfo(priority)
	log.Info().Str("Priority", priorityString).Msg("Processing graft with the given priority.")
	return GraftOptions{
		PriorityVal: priorityVal,
		Debug:       false,
		Priority:    priorityString,
	}
}

func GraftWithOptions(db DB, repo string, options GraftOptions) (graftingMetrics GraftMetrics, err error) {
	numFiles, numDirs, numLinks, numDels, err := db.DBCounts()
	graftingMetrics = GraftMetrics{Files: numFiles, Dirs: numDirs, Links: numLinks, Deletions: numDels, Priority: options.Priority, LeasePath: MissingMetric, Revision: MissingMetric}
	stdoutExtractions := map[string]*regexp.Regexp{LeasePathRegexName: regexp.MustCompile(LeasePathRegex), RevisionRegexName: regexp.MustCompile(RevisionRegex)}
	stdoutExtracted := map[string][]string{}
	log.Info().Msg("Grafting:")
	start_time := time.Now()
	defer func() {
		end_time := time.Now()
		graftingMetrics.Delta = end_time.Sub(start_time).Seconds()
		log.Info().Float64("delta (s)", graftingMetrics.Delta).Msg("Grafting Time")
	}()
	var cvmfsRsyncTempDir string
	cvmfsRsyncTempDir, err = os.MkdirTemp("", "cvmfs_rsync_swissknife")
	if err != nil {
		return
	}
	defer func() {
		if tempErr := os.RemoveAll(cvmfsRsyncTempDir); tempErr != nil {
			log.Error().Err(tempErr).Msg("Error in cleanup of tempDir")
			if err == nil {
				err = tempErr
			}
		}
	}()

	log.Debug().Int64("Priority Value", options.PriorityVal).Msg("Calculated Priority")

	var args = []string{
		"ingestsql",
		"-N", repo, /* fully qualified repository name */
		"-D", db.GetPath(), /* input sqlite DB */
		"-t", cvmfsRsyncTempDir, /* temporary directory */
		"-a",                                          /* Allow additions */
		"-d",                                          /* Allow deletions */
		"-B", fmt.Sprintf("/var/spool/cvmfs/%s/rdonly", repo), /* mount point to block on pending visibility of update */
		"-P", strconv.FormatInt(options.PriorityVal, 10),
	}

	cmd := exec.Command("cvmfs_swissknife", args...)

	stdout, err := cmd.StdoutPipe()
	if err != nil {
		return
	}
	stderr, err := cmd.StderrPipe()
	if err != nil {
		return
	}
	// Get logging scanners
	stdoutIn := bufio.NewScanner(stdout)
	stderrIn := bufio.NewScanner(stderr)

	if err = cmd.Start(); err != nil {
		return
	}

	var wg sync.WaitGroup
	wg.Add(1)
	go func(scanner *bufio.Scanner) {
		defer wg.Done()
		stdoutExtracted = LeveledPipeLoggerWithExtraction(scanner, zerolog.InfoLevel, stdoutExtractions)
	}(stdoutIn)
	wg.Add(1)
	go func(scanner *bufio.Scanner) {
		defer wg.Done()
		LeveledPipeLogger(scanner, zerolog.WarnLevel)
	}(stderrIn)

	wg.Wait()
	if err = cmd.Wait(); err != nil {
		log.Error().Err(err).Str("Swissknife command", cmd.String()).Msg("Error in grafting")
		return
	}

	if match, ok := stdoutExtracted[LeasePathRegexName]; ok {
		graftingMetrics.LeasePath = match[1]
	}
	if match, ok := stdoutExtracted[RevisionRegexName]; ok {
		graftingMetrics.Revision = match[1]
	}

	log.Info().Msg("Finished Grafting")

	time.Sleep(PreSyncDelaySeconds * time.Second)

	return
}

func Graft(db DB, repo string, priority string, debug bool) (graftingMetrics GraftMetrics, err error) {
	options := NewGraftOptions(priority)
	options.Debug = debug
	return GraftWithOptions(db, repo, options)
}

// Remount and sync a repository (currently doesn't actually ensure sync afterwards)
func RemountSyncRepo(repo string, debug bool) error {
	cmd := exec.Command("sudo", "-u", "cvmfs", "/bin/cvmfs_talk", "-i", repo, "remount", "sync")

	if debug {
		cmd.Stdout = log.Logger
		cmd.Stderr = log.Logger
	}

	if err := cmd.Start(); err != nil {
		return err
	}
	if err := cmd.Wait(); err != nil {
		return err
	}

	return nil
}
