package main

import (
	"flag"
	"fmt"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/dustin/go-humanize"
	"github.com/fatih/color"
	"github.com/olekukonko/tablewriter"
	log "github.com/sirupsen/logrus"
	"github.com/spf13/cast"

	"github.com/rfyiamcool/go-netflow"
)

var (
	nf netflow.Interface

	yellow  = color.New(color.FgYellow).SprintFunc()
	red     = color.New(color.FgRed).SprintFunc()
	info    = color.New(color.FgGreen).SprintFunc()
	blue    = color.New(color.FgBlue).SprintFunc()
	magenta = color.New(color.FgHiMagenta).SprintFunc()

	targetPID     string
	recentSeconds int
)

func start() {
	var err error

	nf, err = netflow.New()
	if err != nil {
		log.Fatal(err)
	}

	err = nf.Start()
	if err != nil {
		log.Fatal(err)
	}

	var (
		recentRankLimit = 10

		sigch   = make(chan os.Signal, 1)
		ticker  = time.NewTicker(3 * time.Second)
		timeout = time.NewTimer(300 * time.Second)
	)

	signal.Notify(sigch,
		syscall.SIGINT, syscall.SIGTERM, syscall.SIGQUIT,
		syscall.SIGHUP, syscall.SIGUSR1, syscall.SIGUSR2,
	)

	defer func() {
		nf.Stop()
	}()

	go func() {
		for {
			<-ticker.C
			if len(targetPID) > 0 {
				proc, err := nf.GetProcessByPID(targetPID, recentSeconds)
				clear()
				if err != nil {
					fmt.Printf("pid %s not found or unavailable: %s\n", targetPID, err.Error())
					continue
				}

				showTable([]*netflow.Process{proc})
				continue
			}

			rank, err := nf.GetProcessRank(recentRankLimit, recentSeconds)
			clear()
			if err != nil {
				fmt.Printf("load process rank failed: %s\n", err.Error())
				continue
			}
			showTable(rank)
		}
	}()

	for {
		select {
		case <-sigch:
			return

		case <-timeout.C:
			return
		}
	}
}

func stop() {
	if nf == nil {
		return
	}

	nf.Stop()
}

const thold = 1024 * 1024 // 1mb

func clear() {
	fmt.Printf("\x1b[2J")
}

func showTable(ps []*netflow.Process) {
	table := tablewriter.NewWriter(os.Stdout)
	table.SetHeader([]string{"pid", "name", "exe", "inodes", "sum_in", "sum_out", "in_rate", "out_rate"})
	table.SetRowLine(true)

	items := [][]string{}
	for _, po := range ps {
		inRate := humanBytes(po.TrafficStats.InRate)
		if po.TrafficStats.InRate > int64(thold) {
			inRate = red(inRate)
		}

		outRate := humanBytes(po.TrafficStats.OutRate)
		if po.TrafficStats.OutRate > int64(thold) {
			outRate = red(outRate)
		}

		item := []string{
			po.Pid,
			po.Name,
			po.Exe,
			cast.ToString(po.InodeCount),
			humanBytes(po.TrafficStats.In),
			humanBytes(po.TrafficStats.Out),
			inRate + "/s",
			outRate + "/s",
		}

		items = append(items, item)
	}

	table.AppendBulk(items)
	table.Render()
}

func humanBytes(n int64) string {
	return humanize.Bytes(uint64(n))
}

func main() {
	flag.StringVar(&targetPID, "pid", "", "monitor traffic by pid")
	flag.IntVar(&recentSeconds, "recent-sec", 3, "average window in seconds")
	flag.Parse()

	if recentSeconds <= 0 {
		log.Fatal("recent-sec must > 0")
	}

	log.Info("start netflow sniffer")

	start()
	stop()

	log.Info("netflow sniffer exit")
}
