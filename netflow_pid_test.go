package netflow

import (
	"context"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
)

func TestGetProcessByPID(t *testing.T) {
	nf := &Netflow{
		processHash: NewProcessController(context.Background()),
	}

	_, err := nf.GetProcessByPID("", 3)
	assert.NotEqual(t, nil, err)

	_, err = nf.GetProcessByPID("100", maxRingSize+1)
	assert.NotEqual(t, nil, err)

	nf.processHash.Add("100", &Process{
		Pid:          "100",
		TrafficStats: new(trafficStatsEntry),
		totalIn:      11,
		totalOut:     7,
		Ring: []*trafficEntry{
			{
				Timestamp: time.Now().Unix(),
				In:        11,
				Out:       7,
			},
		},
	})

	got, err := nf.GetProcessByPID("100", 3)
	assert.Equal(t, nil, err)
	assert.NotEqual(t, nil, got)
	assert.Equal(t, "100", got.Pid)
	assert.EqualValues(t, 11, got.TrafficStats.In)
	assert.EqualValues(t, 7, got.TrafficStats.Out)

	_, err = nf.GetProcessByPID("404", 3)
	assert.Equal(t, errNotFound, err)
}
